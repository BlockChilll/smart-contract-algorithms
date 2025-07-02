// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/**
 * @author denissosnowsky
 * @title reward accumulation curve-like algorithm
 * @notice Reward rates the gauge is getting depends on reward token inflation (emission) rate, gauge weight, and gauge type weights
 * Each user receives a share of newly minted reward token proportional to the amount of LP tokens locked
 * Additionally rewards can be boosted
 * General Formula:
 * r - rate of reward token emission
 *
 * wg - gauge weight
 * wt - gauge type weight
 * NOTE: in this file we consider one general weight as only one 'w'
 * r * wg * wt = R (general rate of reward token)
 * R(t) - rate at timestamp 't'
 * b(t) - balance of supplied lp token by user at timestamp 't'
 * S(t) - total lp supply by all users at timestamp 't'
 * If we imagine that derivative interval is 1 second, than R(t), b(t) and S(t) are derivatives of rate, user supply and total supply respectively at timestamp 't'
 * Reward that user accumulated at timestamp 't' is a derivative at timestamp 't' and equals:
 *
 * I(t) = R(t) * b(t) / S(t)
 * In order to find all reward that user accumulated during some time period, we need to find integral of I(t) for time period t2 - t1:
 * I = ∫ ( R(t) * b(t) / S(t) ) dx
 *
 * r - is a rate per second, but it can be changed in the middle of the period (in real ife it can be emission rate that decrease once per year)
 * b - changes every time the user makes a deposit or withdrawal
 *
 * S - changes every time any user makes a deposit or withdrawal (so it can change many times in between two events for the user)
 * When any user deposits or withdraw, we count simplified integral for 1 lp balance reward accumulation without considering user's supply, only total:
 * Iis = ∫ ( R(t) / S(t) ) dx
 *
 * When particular user deposits/withdraws we can calculate how much he/she accumulated from last operation by:
 * I_t2_t1 = b * (Iis_t2 - Iis_t1),  b - is the same during time period t2 - t1 (cause nothing changed from user perspective between his/her two operations)
 *
 *                                   Iis_t2 - integral of 1 lp reward at timestamp t2
 *                                   Iis_t1 - integral of 1 lp reward at timestamp t1
 * By finding sum of such accumulation for all between-operation periods, we will find general user's reward gain
 *
 * Rewards boost are calculated via 'working_balances' and 'working_supply' conceptions
 * 'working_balances' - the effective liquidity of a user, which is used to calculate the rewards they are entitled to
 *     Example: 1 LP token with no boost = 0.4 working_balances
 *              1 LP token with 1.5 boost = 1.5 working_balances
 *              1 LP token with 2.5 boost = 2.5 working_balances
 * 'working_supply' - the sum of all 'working_balances' of users who provided liquidity in the gauge.
 *
 * NOTE: we take WEEK here as period between checkpoint. Generally, it should be period of 'weight' changes. Here in simplicity we hardcode 'weight' in constructor
 * But in curve the 'weight' is updated once per week from gauge controller
 */

contract RewardAccumulation {
    // percent of liquidity counted as working_balance when boost is zero - 40%
    uint256 constant TOKENLESS_PRODUCTION = 40;
    // week seconds
    uint256 constant WEEK = 604800;

    // user's LP deposited on current period (recalculated between user's two operations) correlated with boost factor,  1e18 precision
    mapping(address => uint256) workingBalances;
    // all LP deposited on current period (recalculated between user's two operations) correlated with boost factor,  1e18 precision
    uint256 workingSupply;
    // LP amount user deposited,  1e18 precision
    mapping(address => uint256) balanceOf;
    // all LP amount deposited by all,  1e18 precision
    uint256 totalSupply;

    // period counter, starts from 0
    uint256 period;
    // index is period counter, value is timestamp for that period
    uint256[] periodTimestamp;

    // reward integral for 1 lp token,  1e18 precision
    uint256[] integrateInvSupply;
    // reward integral for 1 lp token that was checkpointed last time user made operation,  1e18 precision
    mapping(address => uint256) integrateInvSupplyOf;
    // timestamp of user's last integral calculation
    mapping(address => uint256) integrateCheckpointOf;
    // user reward integral,  1e18 precision
    mapping(address => uint256) integrateFraction;

    // rate of reward accumulation per second,  1e18 precision
    uint256 immutable rate;
    // weight of rewards for current file,  1e18 precision
    uint256 immutable weight;

    constructor(uint256 _rate, uint256 _weight) {
        periodTimestamp.push(block.timestamp);
        integrateInvSupply.push(0);
        rate = _rate;
        weight = _weight;
    }

    /**
     *  NOTE: should be called inside deposit/withdrawal functions, but after _checkpoint
     *  @param user address of user to update working balance
     *  @param userLiquidity how much LP tokens user has deposited generally
     *  @param totalLiquidity how much LP tokens all users deposited
     *  @param boostBalance how much of boost balance user has
     *  @param boostTotal boost total balance
     *  In curve 'boost_balance' and 'boost_total' are 'voting_balance' and 'voting_total' respectively. In other words,
     *  'voting_balance' is veCRV balance, and 'voting_total' is veCRV total supply. Ir means how many voting tokens user has
     *  THe more he/she has, the bigger boost
     *  Generally 'boost_balance' and 'boost_total' can be any boosting factor
     *
     *  Formulas:
     *  limit = 0.4 * user_liquidity;
     *  limit = limit + total_liquidity * (boost_balance / boost_total) * 0.6
     *  limit = min(user_liquidity, limit) - this is a working_balance
     *  boost factor = limit / user_liquidity * 0.4
     */
    function _updateWorkingBalance(
        address user,
        uint256 userLiquidity,
        uint256 totalLiquidity,
        uint256 boostBalance,
        uint256 boostTotal
    ) internal {
        uint256 limit = (userLiquidity * TOKENLESS_PRODUCTION) / 100;

        if (boostBalance > 0) {
            limit = (limit +
                (((totalLiquidity * boostBalance) / boostTotal) *
                    (100 - TOKENLESS_PRODUCTION)) /
                100);
        }

        limit = userLiquidity < limit ? userLiquidity : limit; // new working balance

        uint256 oldWBalance = workingBalances[user];
        workingBalances[user] = limit;
        workingSupply = workingSupply + limit - oldWBalance;
    }

    /**
     *
     * @param user address of user
     * boost factor = workingBalances[user] / ( userLiquidity * 0.4)
     * max boost factor is 2.5
     */
    function _getBoostFactor(address user) internal view returns (uint256) {
        return
            workingBalances[user] /
            ((balanceOf[user] * TOKENLESS_PRODUCTION) / 100);
    }

    /**
     * @param user address of user to checkpoint
     * Calculate user rewards for each week from last time it was calculated before
     *
     * NOTE: Should be called everytime any user deposits/withdraws, before '_update_working_balance'
     */
    function _checkpoint(address user) internal {
        uint256 _period = period;
        uint256 _periodTime = periodTimestamp[_period];
        uint256 _workingBalance = workingBalances[user];
        uint256 _workingSupply = workingSupply;
        uint256 _integrateInvSupply = integrateInvSupply[_period];

        // update integral of 1 LP token
        if (block.timestamp > _periodTime) {
            uint256 prevWeekTime = _periodTime;
            uint256 prevWeekTimePlusWeek = ((prevWeekTime + WEEK) / WEEK) *
                WEEK;
            uint256 weekTime = prevWeekTimePlusWeek < block.timestamp
                ? prevWeekTimePlusWeek
                : block.timestamp;

            for (uint256 i = 0; i < 500; i++) {
                uint256 dt = weekTime - prevWeekTime;

                if (_workingSupply > 0) {
                    _integrateInvSupply +=
                        (rate * weight * dt) /
                        _workingSupply;
                }

                if (weekTime == block.timestamp) {
                    break;
                }

                prevWeekTime = weekTime;
                prevWeekTimePlusWeek = weekTime + WEEK;
                weekTime = prevWeekTimePlusWeek < block.timestamp
                    ? prevWeekTimePlusWeek
                    : block.timestamp;
            }
        }

        _period += 1;
        period = _period;
        periodTimestamp.push(block.timestamp);
        integrateInvSupply.push(_integrateInvSupply);

        // update user's integral
        integrateFraction[user] += ((_workingBalance *
            (_integrateInvSupply - integrateInvSupplyOf[user])) / 10 ** 18);
        integrateInvSupplyOf[user] = _integrateInvSupply;
        integrateCheckpointOf[user] = block.timestamp;
    }

    // ------------------------------------------------------------------
    //                               EXTERNAL
    // ------------------------------------------------------------------

    function updateWorkingBalance(
        address user,
        uint256 userLiquidity,
        uint256 totalLiquidity,
        uint256 boostBalance,
        uint256 boostTotal
    ) external {
        _updateWorkingBalance(
            user,
            userLiquidity,
            totalLiquidity,
            boostBalance,
            boostTotal
        );
    }

    function getBoostFactor(address user) external view returns (uint256) {
        return _getBoostFactor(user);
    }

    function checkpoint(address user) external {
        _checkpoint(user);
    }

    function getRate() external view returns (uint256) {
        return rate;
    }

    function getWeight() external view returns (uint256) {
        return weight;
    }

    function getUserWb(address user) external view returns (uint256) {
        return workingBalances[user];
    }

    function getWorkingSupply() external view returns (uint256) {
        return workingSupply;
    }

    function getUserReward(address user) external view returns (uint256) {
        return integrateFraction[user];
    }
}
