# pragma version 0.4.1
# @license MIT

"""
Algorithm for balance/vote that decays linearly over time
It has weight depending on time, the more time you stake, the bigger weight
As example 4 years of maximum stake time is taken
# w ^
# 1 +        /
#   |      /
#   |    /
#   |  /
#   |/
# 0 +--------+------> time
#       maxtime (4 years)

Global bias and slope are calculated as sum of all users' biases and slopes
Important thing to consider: when user's stake ends, we need remove its slope from global slope, otherwise all further decays will
include slopes of the finished stakes. For this we use 'slope_changes'. It stores sum of all slopers that should be removed for particular epoch
"""


struct Point:
    bias: int128
    slope: int128  # - dweight / dt
    ts: uint256
    blk: uint256  # block


struct LockedBalance:
    amount: int128
    end: uint256


WEEK: constant(uint256) = 7 * 86400  # all future times are rounded by week
MAXTIME: constant(uint256) = 4 * 365 * 86400  # 4 years
MULTIPLIER: constant(uint256) = 10**18

# user's staked position
locked: public(HashMap[address, LockedBalance])
# counter, current period of the system, starts with 0
epoch: public(uint256)
# accumulation of Points for each epoch globally for the whole system
point_history: public(
    Point[100000000000000000000000000000]
)  # epoch -> unsigned point
# accumulation of Points for each user
user_point_history: public(
    HashMap[address, Point[1000000000]]
)  # user -> Point[user_epoch]
# counter, current period of the yser
user_point_epoch: public(HashMap[address, uint256])
# when user stakes, his slope is added to global slope. After user's stake ends, we need to remove the his slope from global.
# This variable accumulates negative slopes to remove at particular time
slope_changes: public(HashMap[uint256, int128])  # time -> signed slope change


@deploy
def __init__():
    self.point_history[0].blk = block.number
    self.point_history[0].ts = block.timestamp


@internal
def _checkpoint(
    addr: address, old_locked: LockedBalance, new_locked: LockedBalance
):
    """
    @notice Record global and per-user data to checkpoint
    @param addr User's wallet address. No user checkpoint if 0x0
    @param old_locked Previous locked amount / end lock time for the user
    @param new_locked New locked amount / end lock time for the user
    """

    # must round end timestamp with WEEK
    new_locked.end = new_locked.end // WEEK * WEEK

    u_old: Point = empty(Point)
    u_new: Point = empty(Point)
    old_dslope: int128 = 0
    new_dslope: int128 = 0
    _epoch: uint256 = self.epoch

    if addr != convert(0, address):
        if old_locked.amount > 0 and old_locked.end > block.timestamp:
            u_old.slope = old_locked.amount // convert(MAXTIME, int128)
            u_old.bias = u_old.slope * convert(
                (old_locked.end - block.timestamp), int128
            )
        if new_locked.end > block.timestamp and new_locked.amount > 0:
            u_new.slope = new_locked.amount // convert(MAXTIME, int128)
            u_new.bias = u_new.slope * convert(
                new_locked.end - block.timestamp, int128
            )

        old_dslope = self.slope_changes[old_locked.end]
        if new_locked.end != 0:
            if new_locked.end == old_locked.end:
                new_dslope = old_dslope
            else:
                new_dslope = self.slope_changes[new_locked.end]

        # change global checkpoint

    last_point: Point = Point(
        bias=0, slope=0, ts=block.timestamp, blk=block.number
    )
    if _epoch > 0:
        last_point = self.point_history[_epoch]
    last_checkpoint: uint256 = last_point.ts

    initial_last_point: Point = last_point
    block_slope: uint256 = 0  # dblock/dt
    if block.timestamp > last_point.ts:
        block_slope = MULTIPLIER * (block.number - last_point.blk) // (
            block.timestamp - last_point.ts
        )

    t_i: uint256 = last_checkpoint // WEEK * WEEK
    for i: uint256 in range(500):
        t_i += WEEK
        d_slope: int128 = 0
        if t_i > block.timestamp:
            t_i = block.timestamp
        else:
            d_slope = self.slope_changes[t_i]
        last_point.bias -= last_point.slope * convert(
            (t_i - last_checkpoint), int128
        )
        last_point.slope += d_slope
        if last_point.bias < 0:
            last_point.bias = 0
        if last_point.slope < 0:
            last_point.slope = 0

        last_checkpoint = t_i
        last_point.ts = t_i
        last_point.blk = (
            initial_last_point.blk
            + block_slope * (t_i - initial_last_point.ts) // MULTIPLIER
        )
        _epoch += 1
        if t_i == block.timestamp:
            last_point.blk = block.number
            break
        else:
            self.point_history[_epoch] = last_point

    if addr != convert(0, address):
        last_point.bias = last_point.bias + u_new.bias - u_old.bias
        last_point.bias = last_point.slope + u_new.slope - u_old.slope
        if last_point.slope < 0:
            last_point.slope = 0
        if last_point.bias < 0:
            last_point.bias = 0
            
    self.point_history[_epoch] = last_point

    if addr != convert(0, address):
        if old_locked.end > block.timestamp:
            old_dslope += u_old.slope
            if new_locked.end == old_locked.end:
                old_dslope -= u_new.slope
            self.slope_changes[old_locked.end] = old_dslope

        if new_locked.end > block.timestamp:
            if new_locked.end > old_locked.end:
                new_dslope -= u_new.slope
                self.slope_changes[new_locked.end] = new_dslope

        # Now handle user history
        user_epoch: uint256 = self.user_point_epoch[addr] + 1

        self.user_point_epoch[addr] = user_epoch
        u_new.ts = block.timestamp
        u_new.blk = block.number
        self.user_point_history[addr][user_epoch] = u_new


@internal
@view
def _balance_of(user: address) -> uint256:
    epoch: uint256 = self.user_point_epoch[user]

    if epoch == 0:
        return 0

    last_point: Point = self.user_point_history[user][epoch]
    bias: int128 = last_point.bias - last_point.slope * convert(
        (block.timestamp - last_point.ts), int128
    )
    if bias < 0:
        bias = 0

    return convert(bias, uint256)


@internal
@view
def _supply_at(time: uint256 = block.timestamp) -> uint256:
    epoch: uint256 = self.epoch

    if epoch == 0:
        return 0

    last_point: Point = self.point_history[epoch]
    t_i: uint256 = last_point.ts // WEEK * WEEK

    for i: uint256 in range(500):
        t_i += WEEK
        if t_i > time:
            t_i = time
        last_point.bias -= last_point.slope * convert(
            t_i - last_point.ts, int128
        )
        last_point.slope += self.slope_changes[t_i]
        last_point.ts = t_i
        if t_i == time:
            break
    if last_point.bias < 0:
        last_point.bias = 0

    return convert(last_point.bias, uint256)


@internal
@view
def _supply() -> uint256:
    return self._supply_at()


# ------------------------------------------------------------------
#                               EXTERNAL
# ------------------------------------------------------------------

@external
def checkpoint(
    addr: address, old_locked: LockedBalance, new_locked: LockedBalance
):
    self._checkpoint(addr, old_locked, new_locked)


@external
@view
def totalSupply() -> uint256:
    return self._supply()


@external
@view
def balanceOf(user: address) -> uint256:
    return self._balance_of(user)
