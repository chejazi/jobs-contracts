// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IStakeTracker is IERC20 {
    function init(address splitter, address user, address token) external;
    function add(address user, uint quantity) external;
    function remove(address user, uint quantity) external;
    function track(address token, uint quantity) external;
    function claim(address user, uint[] memory snapshotIds) external returns (address[] memory, uint[] memory);
    function getUserReward(address user, uint snapshotId) external view returns (address, uint);
    function getReward(uint snapshotId) external view returns (address, uint);
    function getCurrentSnapshotId() external view returns (uint);
    function getSplitter() external view returns (address);
    function getUser() external view returns (address);
    function getToken() external view returns (address);
    function hasClaimed(address user, uint snapshotId) external view returns (bool);
    function getClaimed(address user) external view returns (uint[] memory);
    function getClaimedAt(address user, uint index) external view returns (uint);
    function getNumClaimed(address user) external view returns (uint);
    function balanceOfAt(address account, uint256 snapshotId) external view returns (uint256);
    function totalSupplyAt(uint256 snapshotId) external view returns (uint256);
}

