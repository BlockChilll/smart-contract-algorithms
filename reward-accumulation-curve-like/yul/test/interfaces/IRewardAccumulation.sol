// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IRewardAccumulation {
    function updateWorkingBalance(
        address user,
        uint256 userLiquidity,
        uint256 totalLiquidity,
        uint256 boostBalance,
        uint256 boostTotal
    ) external;

    function getBoostFactor(address user) external view returns (uint256);

    function checkpoint(address user) external;

    function getRate() external view returns (uint256);

    function getWeight() external view returns (uint256);

    function getUserWb(address user) external view returns (uint256);

    function getWorkingSupply() external view returns (uint256);

    function getUserReward(address user) external view returns (uint256);

    function getPeriodTimestamp(uint256 index) external view returns (uint256);
}
