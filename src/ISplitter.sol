// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ISplitter {
    function init(address user) external;
    function split(address stakedToken, address rewardToken, uint rewardQuantity) external;
    function claim(address to, address[] memory stakedTokens, uint[][] memory snapshotIds) external;
    function getDirectory() external view returns (address);
    function getUser() external view returns (address);
    function getStakeTracker(address token) external view returns (address);
}
