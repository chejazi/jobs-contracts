// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Snapshot.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract StakeTracker is ERC20Snapshot {
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.UintSet;

    address private _splitter;
    address private _user;
    address private _token;
    mapping(uint => uint) public rewardQuantity;
    mapping(uint => address) public rewardToken;
    mapping(address => EnumerableSet.UintSet) _userClaimed;

    modifier onlySplitter {
        require(msg.sender == _splitter, "Only callable by Splitter");
        _;
    }

    constructor() ERC20("", "") { }

    function init(address splitter, address user, address token) external {
        require(_splitter == address(0), "Cannot reinitialize");
        require(splitter != address(0), "splitter cannot be null");
        _splitter = splitter;
        _user = user;
        _token = token;
    }

    function add(address user, uint quantity) external onlySplitter {
        _mint(user, quantity);
    }

    function remove(address user, uint quantity) external onlySplitter {
        _burn(user, quantity);
    }

    function track(address token, uint quantity) external onlySplitter {
        uint snapshotId = _snapshot();

        rewardToken[snapshotId] = token;
        rewardQuantity[snapshotId] = quantity;
    }

    function claim(address user, uint[] memory snapshotIds) external onlySplitter returns (address[] memory, uint[] memory) {
        address[] memory tokens = new address[](snapshotIds.length);
        uint[] memory quantities = new uint[](snapshotIds.length);

        bool allClaimable = true;
        EnumerableSet.UintSet storage userClaimed = _userClaimed[user];
        for (uint i = 0; i < snapshotIds.length; i++) {
            (tokens[i], quantities[i]) = getUserReward(user, snapshotIds[i]);
            allClaimable = allClaimable && userClaimed.add(snapshotIds[i]);
        }
        require(allClaimable, "Rewards already claimed");

        return (tokens, quantities);
    }

    function transfer(address, uint256) public pure override returns (bool) {
        revert("Transfers disabled");
    }

    function transferFrom(address, address, uint256) public pure override returns (bool) {
        revert("Transfers disabled");
    }

    function getUserReward(address user, uint snapshotId) public view returns (address, uint) {
        uint balanceAt = balanceOfAt(user, snapshotId);
        uint supplyAt = totalSupplyAt(snapshotId);
        if (supplyAt == 0) {
            supplyAt = 1; // Avoid dividing by 0
        }
        address token = rewardToken[snapshotId];
        uint quantity = rewardQuantity[snapshotId]
            .mul(balanceAt)
            .div(supplyAt);

        return (token, quantity);
    }

    function getReward(uint snapshotId) external view returns (address, uint) {
        return (rewardToken[snapshotId], rewardQuantity[snapshotId]);
    }

    function getCurrentSnapshotId() external view returns (uint) {
        return _getCurrentSnapshotId();
    }

    function getSplitter() external view returns (address) {
        return _splitter;
    }

    function getUser() external view returns (address) {
        return _user;
    }

    function getToken() external view returns (address) {
        return _token;
    }

    function hasClaimed(address user, uint snapshotId) external view returns (bool) {
        return _userClaimed[user].contains(snapshotId);
    }
    function getClaimed(address user) external view returns (uint[] memory) {
        return _userClaimed[user].values();
    }
    function getClaimedAt(address user, uint index) external view returns (uint) {
        return _userClaimed[user].at(index);
    }
    function getNumClaimed(address user) external view returns (uint) {
        return _userClaimed[user].length();
    }

    function name() public view override returns (string memory) {
        return string.concat(ERC20(_token).symbol(), " on ", Strings.toHexString(_user));
    }

    function symbol() public view override returns (string memory) {
        bytes memory shortAddrStr = new bytes(6);
        bytes memory addrStr = bytes(Strings.toHexString(_user));
        for (uint i = 0; i < 6; i++) {
            shortAddrStr[i] = addrStr[i];
        }
        return string.concat(ERC20(_token).symbol(), "-", string(shortAddrStr));
    }
}
