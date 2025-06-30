# pragma version 0.4.1
# @license MIT

"""
@title reward accumulation curve-like algorithm
@author denissosnowsky
@notice Reward rates the gauge is getting depends on reward token inflation (emission) rate, gauge weight, and gauge type weights
Each user receives a share of newly minted reward token proportional to the amount of LP tokens locked
Additionally rewards can be boosted

General Formula:
r - rate of reward token emission
wg - gauge weight
wt - gauge type weight
NOTE: in this file we consider one general weight as only one 'w'
r * wg * wt = R (general rate of reward token)
R(t) - rate at timestamp 't'
b(t) - balance of supplied lp token by user at timestamp 't'
S(t) - total lp supply by all users at timestamp 't'

If we imagine that derivative interval is 1 second, than R(t), b(t) and S(t) are derivatives of rate, user supply and total supply respectively at timestamp 't'
Reward that user accumulated at timestamp 't' is a derivative at timestamp 't' and equals:
I(t) = R(t) * b(t) / S(t)

In order to find all reward that user accumulated during some time period, we need to find integral of I(t) for time period t2 - t1:
I = ∫ ( R(t) * b(t) / S(t) ) dx

r - is a rate per second, but it can be changed in the middle of the period (in real ife it can be emission rate that decrease once per year)
b - changes every time the user makes a deposit or withdrawal
S - changes every time any user makes a deposit or withdrawal (so it can change many times in between two events for the user)

When any user deposits or withdraw, we count simplified integral for 1 lp balance reward accumulation without considering user's supply, only total:
Iis = ∫ ( R(t) / S(t) ) dx

When particular user deposits/withdraws we can calculate how much he/she accumulated from last operation by:
I_t2_t1 = b * (Iis_t2 - Iis_t1),  b - is the same during time period t2 - t1 (cause nothing changed from user perspective between his/her two operations)
                                  Iis_t2 - integral of 1 lp reward at timestamp t2
                                  Iis_t1 - integral of 1 lp reward at timestamp t1
By finding sum of such accumulation for all between-operation periods, we will find general user's reward gain

Rewards boost are calculated via 'working_balances' and 'working_supply' conceptions
'working_balances' - the effective liquidity of a user, which is used to calculate the rewards they are entitled to
    Example: 1 LP token with no boost = 0.4 working_balances
             1 LP token with 1.5 boost = 1.5 working_balances
             1 LP token with 2.5 boost = 2.5 working_balances
'working_balances' - the sum of all 'working_balances' of users who provided liquidity in the gauge.

NOTE: we take WEEK here as period between checkpoint. Generally, it should be period of 'weight' changes. Here in simplicity we hardcode 'weight' in constructor
But in curve the 'weight' is updated once per week from gauge controller
"""

# percent of liquidity counted as working_balance when boost is zero - 40%
TOKENLESS_PRODUCTION: constant(uint256) = 40
# week seconds
WEEK: constant(uint256) = 604800

# user's LP deposited on current period (recalculated between user's two operations) correlated with boost factor,  1e18 precision
working_balances: public(HashMap[address, uint256])
# all LP deposited on current period (recalculated between user's two operations) correlated with boost factor,  1e18 precision
working_supply: public(uint256)

# LP amount user deposited,  1e18 precision
balanceOf: public(HashMap[address, uint256])
# all LP amount deposited by all,  1e18 precision
totalSupply: public(uint256)

# period counter, starts from 0
period: public(int128)
# index is period counter, value is timestamp for that period
period_timestamp: public(uint256[100000000000000000000000000000])

# reward integral for 1 lp token,  1e18 precision
integrate_inv_supply: public(uint256[100000000000000000000000000000])
# reward integral for 1 lp token that was checkpointed last time user made operation,  1e18 precision
integrate_inv_supply_of: public(HashMap[address, uint256])
# timestamp of user's last integral calculation
integrate_checkpoint_of: public(HashMap[address, uint256])
# user reward integral,  1e18 precision
integrate_fraction: public(HashMap[address, uint256])

# rate of reward accumulation per second,  1e18 precision
rate: immutable(uint256)
# weight of rewards for current file,  1e18 precision
weight: immutable(uint256)


@deploy
def __init__(_rate: uint256, _weight: uint256):
    self.period_timestamp[0] = block.timestamp
    rate = _rate
    weight = _weight


@internal
def _update_working_balance(
    user: address,
    user_liquidity: uint256,
    total_liquidity: uint256,
    boost_balance: uint256,
    boost_total: uint256,
):
    """
    NOTE: should be called inside deposit/withdrawal functions, but after _update_checkpoint
    @param user address of user to update working balance
    @param user_liquidity how much LP tokens user has deposited generally
    @param total_liquidity how much LP tokens all users deposited
    @param boost_balance how much of boost balance user has
    @param boost_total boost total balance
    In curve 'boost_balance' and 'boost_total' are 'voting_balance' and 'voting_balance' respectively. In other words,
    'voting_balance' is veCRV balance, and 'voting_balance' is veCRV total supply. Ir means how many voting tokens user has
    THe more he/she has, the bigger boost
    Generally 'boost_balance' and 'boost_total' can be any boosting factor

    Formulas:
    limit = 0.4 * user_liquidity;
    limit = limit + total_liquidity * (boost_balance / boost_total) * 0.6
    limit = min(user_liquidity, limit) - this is a working_balance
    boost factor = limit / user_liquidity * 0.4
    """

    limit: uint256 = user_liquidity * TOKENLESS_PRODUCTION // 100
    if boost_balance > 0:
        limit = (
            limit
            + total_liquidity
            * boost_balance // boost_total
            * (100 - TOKENLESS_PRODUCTION) // 100
        )
    limit = min(user_liquidity, limit)  # new working balance

    old_w_balance: uint256 = self.working_balances[user]
    self.working_balances[user] = limit
    self.working_supply = self.working_supply + limit - old_w_balance


@internal
@view
def _get_boost_factor(user: address) -> uint256:
    """
    @param user address of user
    boost factor = self.working_balances[user] / ( user_liquidity * 0.4)
    max boost factor is 2.5
    """
    return self.working_balances[user] // (
        self.balanceOf[user] * TOKENLESS_PRODUCTION // 100
    )


@internal
def _checkpoint(user: address):
    """
    @param user address of user to checkpoint
    Calculate user rewards for each week from last time it was calculated before

    NOTE: Should be called everytime any user deposits/withdraws, before '_update_working_balance'
    """
    _period: int128 = self.period
    _period_time: uint256 = self.period_timestamp[_period]
    _working_balance: uint256 = self.working_balances[user]
    _working_supply: uint256 = self.working_supply
    _integrate_inv_supply: uint256 = self.integrate_inv_supply[_period]

    # update integral of 1 LP token
    if block.timestamp > _period_time:
        prev_week_time: uint256 = _period_time
        week_time: uint256 = min(
            (prev_week_time + WEEK) // WEEK * WEEK, block.timestamp
        )  # if block.timestamp, week has not elapsed since prev_week_time

        for i: uint256 in range(500):
            dt: uint256 = week_time - prev_week_time

            if _working_supply > 0:
                _integrate_inv_supply += rate * weight * dt // _working_supply

            if week_time == block.timestamp:
                break
            prev_week_time = week_time
            week_time = min(week_time + WEEK, block.timestamp)
    _period += 1
    self.period = _period
    self.period_timestamp[_period] = block.timestamp
    self.integrate_inv_supply[_period] = _integrate_inv_supply

    # update user's integral
    self.integrate_fraction[user] += (
        _working_balance
        * (_integrate_inv_supply - self.integrate_inv_supply_of[user]) // 10
        ** 18
    )
    self.integrate_inv_supply_of[user] = _integrate_inv_supply
    self.integrate_checkpoint_of[user] = block.timestamp


# ------------------------------------------------------------------
#                               EXTERNAL
# ------------------------------------------------------------------

@external
def update_working_balance(
    user: address,
    user_liquidity: uint256,
    total_liquidity: uint256,
    boost_balance: uint256,
    boost_total: uint256,
):
    self._update_working_balance(
        user,
        user_liquidity,
        total_liquidity,
        boost_balance,
        boost_total,
    )

@external
@view
def get_boost_factor(user: address) -> uint256:
    return self._get_boost_factor(user)
    
@external
def checkpoint(user: address):
    self._checkpoint(user)    
