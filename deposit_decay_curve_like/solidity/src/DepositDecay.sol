// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {console} from "forge-std/console.sol";

/**
 * Algorithm for balance/vote that decays linearly over time
 * It has weight depending on time, the more time you stake, the bigger weight
 * As example 4 years of maximum stake time is taken
 * # w ^
 * # 1 +        /
 * #   |      /
 * #   |    /
 * #   |  /
 * #   |/
 * # 0 +--------+------> time
 * #       maxtime (4 years)
 *
 * Global bias and slope are calculated as sum of all users' biases and slopes
 * Important thing to consider: when user's stake ends, we need remove its slope from global slope, otherwise all further decays will
 * include slopes of the finished stakes. For this we use 'slope_changes'. It stores sum of all slopers that should be removed for particular epoch
 */
contract DepositDecay {
    struct Point {
        int128 bias;
        int128 slope;
        uint256 ts;
        uint256 blk;
    }

    struct LockedBalance {
        int128 amount;
        uint256 end;
    }

    uint256 constant WEEK = 7 * 86400; // all future times are rounded by week
    uint256 constant MAXTIME = 4 * 365 * 86400; // 4 years
    uint256 constant MULTIPLIER = 10 ** 18;

    // user's staked position
    mapping(address => LockedBalance) locked;
    // counter, current period of the system, starts with 0
    uint256 epoch;
    // accumulation of Points for each epoch globally for the whole system
    Point[] pointHistory; // epoch -> unsigned point
    // accumulation of Points for each user
    mapping(address => Point[]) userPointHistory; // user -> Point[userEpoch]
    // counter, current period of the yser
    mapping(address => uint256) userPointEpoch;
    // when user stakes, his slope is added to global slope. After user's stake ends, we need to remove the his slope from global.
    // This variable accumulates negative slopes to remove at particular time
    mapping(uint256 => int128) slopeChanges; // time -> signed slope change

    constructor() {
        pointHistory.push(
            Point({bias: 0, slope: 0, ts: block.timestamp, blk: block.number})
        );
    }

    /**
     *
     * @notice Record global and per-user data to checkpoint
     * @param addr User's wallet address. No user checkpoint if 0x0
     * @param oldLocked Previous locked amount / end lock time for the user
     * @param newLocked New locked amount / end lock time for the user
     */
    function _checkpoint(
        address addr,
        LockedBalance memory oldLocked,
        LockedBalance memory newLocked
    ) internal {
        // must round end timestamp with WEEK
        newLocked.end = (newLocked.end / WEEK) * WEEK;

        Point memory uOld;
        Point memory uNew;
        int128 oldDslope;
        int128 newDslope;
        uint256 _epoch = epoch;

        if (addr != address(0)) {
            if (oldLocked.amount > 0 && oldLocked.end > block.timestamp) {
                uOld.slope = oldLocked.amount / int128(uint128(MAXTIME));
                uOld.bias =
                    uOld.slope *
                    int128(uint128((oldLocked.end - block.timestamp)));
            }
            if (newLocked.amount > 0 && newLocked.end > block.timestamp) {
                uNew.slope = newLocked.amount / int128(uint128(MAXTIME));
                uNew.bias =
                    uNew.slope *
                    int128(uint128((newLocked.end - block.timestamp)));
            }

            oldDslope = slopeChanges[oldLocked.end];
            if (newLocked.end != 0) {
                if (newLocked.end == oldLocked.end) {
                    newDslope = oldDslope;
                } else {
                    newDslope = slopeChanges[newLocked.end];
                }
            }
        }

        // change global checkpoint
        Point memory lastPoint = Point({
            bias: 0,
            slope: 0,
            ts: block.timestamp,
            blk: block.number
        });
        if (_epoch > 0) {
            lastPoint = pointHistory[_epoch];
        }
        uint256 lastCheckpoint = lastPoint.ts;

        Point memory initialLastPoint = lastPoint;
        uint256 blockSlope;
        if (block.timestamp > lastPoint.ts) {
            blockSlope =
                (MULTIPLIER * (block.number - lastPoint.blk)) /
                (block.timestamp - lastPoint.ts);
        }

        uint256 t_i = (lastCheckpoint / WEEK) * WEEK;

        for (uint256 i = 0; i < 500; i++) {
            t_i += WEEK;
            int128 dSlope;

            if (t_i > block.timestamp) {
                t_i = block.timestamp;
            } else {
                dSlope = slopeChanges[t_i];
            }

            lastPoint.bias -=
                lastPoint.slope *
                int128(uint128((t_i - lastCheckpoint)));
            lastPoint.slope += dSlope;
            if (lastPoint.bias < 0) {
                lastPoint.bias = 0;
            }
            if (lastPoint.slope < 0) {
                lastPoint.slope = 0;
            }

            lastCheckpoint = t_i;
            lastPoint.ts = t_i;
            lastPoint.blk = (initialLastPoint.blk +
                (blockSlope * (t_i - initialLastPoint.ts)) /
                MULTIPLIER);
            _epoch += 1;
            if (t_i == block.timestamp) {
                lastPoint.blk = block.number;
                break;
            } else {
                pointHistory.push(lastPoint);
            }
        }

        epoch = _epoch;

        if (addr != address(0)) {
            lastPoint.bias = lastPoint.bias + uNew.bias - uOld.bias;
            lastPoint.slope = lastPoint.slope + uNew.slope - uOld.slope;
            if (lastPoint.slope < 0) {
                lastPoint.slope = 0;
            }
            if (lastPoint.bias < 0) {
                lastPoint.bias = 0;
            }
        }

        pointHistory.push(lastPoint);

        if (addr != address(0)) {
            if (oldLocked.end > block.timestamp) {
                oldDslope += uOld.slope;
                if (newLocked.end == oldLocked.end) {
                    oldDslope -= uNew.slope;
                }
                slopeChanges[oldLocked.end] = oldDslope;
            }
            if (newLocked.end > block.timestamp) {
                if (newLocked.end > oldLocked.end) {
                    newDslope -= uNew.slope;
                    slopeChanges[newLocked.end] = newDslope;
                }
            }

            // Now handle user history
            uint256 userEpoch = userPointEpoch[addr];
            if (userEpoch == 0) {
                userPointHistory[addr].push( // need to intialize first point as empty
                    Point({
                        bias: 0,
                        slope: 0,
                        ts: block.timestamp,
                        blk: block.number
                    })
                );
            }

            userPointEpoch[addr] = userEpoch + 1;
            uNew.ts = block.timestamp;
            uNew.blk = block.number;
            userPointHistory[addr].push(uNew);
        }
    }

    function _balanceOf(address user) internal view returns (uint256) {
        uint256 _epoch = userPointEpoch[user];

        if (_epoch == 0) {
            return 0;
        }

        Point memory lastPoint = userPointHistory[user][_epoch];
        int128 bias = lastPoint.bias -
            lastPoint.slope *
            int128(uint128(block.timestamp - lastPoint.ts));

        if (bias < 0) {
            bias = 0;
        }

        return uint256(uint128(bias));
    }

    function _supplyAt(uint256 time) internal view returns (uint256) {
        uint256 _epoch = epoch;

        if (_epoch == 0) {
            return 0;
        }

        Point memory lastPoint = pointHistory[_epoch];
        uint256 t_i = (lastPoint.ts / WEEK) * WEEK;

        for (uint256 i = 0; i < 500; i++) {
            t_i += WEEK;
            if (t_i > time) {
                t_i = time;
            }
            lastPoint.bias -=
                lastPoint.slope *
                int128(uint128(t_i - lastPoint.ts));

            lastPoint.slope += slopeChanges[t_i];
            lastPoint.ts = t_i;
            if (t_i == time) {
                break;
            }
        }

        if (lastPoint.bias < 0) {
            lastPoint.bias = 0;
        }

        return uint256(int256(lastPoint.bias));
    }

    function _supply() internal view returns (uint256) {
        return _supplyAt(block.timestamp);
    }

    // ------------------------------------------------------------------
    //                               EXTERNAL
    // ------------------------------------------------------------------

    function checkpoint(
        address user,
        LockedBalance memory oldLocked,
        LockedBalance memory newLocked
    ) external {
        _checkpoint(user, oldLocked, newLocked);
    }

    function balanceOf(address user) external view returns (uint256) {
        return _balanceOf(user);
    }

    function totalSupply() external view returns (uint256) {
        return _supply();
    }
}
