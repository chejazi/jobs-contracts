// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Snapshot.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract Stakers is ERC20Snapshot {
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;

    address private _app;
    address private _user;
    address private _token;
    mapping(uint => uint) public rewardQuantity;
    mapping(uint => address) public rewardToken;
    mapping(address => EnumerableSet.UintSet) _userClaimed;

    modifier onlyApp {
        require(msg.sender == _app, "Only Staking App");
        _;
    }

    constructor(address app, address user, address token) ERC20("", "") {
        _app = app;
        _user = user;
        _token = token;
    }

    function init(address app, address user, address token) external {
        require(_app == address(0), "Cannot reinitialize");
        _app = app;
        _user = user;
        _token = token;
    }

    function add(address user, uint quantity) external onlyApp {
        _mint(user, quantity);
    }

    function remove(address user, uint quantity) external onlyApp {
        _burn(user, quantity);
    }

    function reward(address token, uint quantity) external onlyApp {
        uint snapshotId = _snapshot();

        rewardToken[snapshotId] = token;
        rewardQuantity[snapshotId] = quantity;
    }

    function claim(address user, uint[] memory snapshotIds) external onlyApp returns (address[] memory, uint[] memory) {
        (address[] memory tokens, uint[] memory quantities) = getUserRewards(user, snapshotIds);

        EnumerableSet.UintSet storage userClaimed = _userClaimed[user];
        bool notClaimed = true;
        for (uint i = 0; i < snapshotIds.length; i++) {
            notClaimed = notClaimed && userClaimed.add(snapshotIds[i]);
        }
        require(notClaimed, "Rewards already claimed");

        return (tokens, quantities);
    }

    function transfer(address, uint256) public pure override returns (bool) {
        revert("Transfers disabled");
    }

    function transferFrom(address, address, uint256) public pure override returns (bool) {
        revert("Transfers disabled");
    }

    function getUserRewards(address user, uint[] memory snapshotIds) public view returns (address[] memory, uint[] memory) {
        uint numRewards = snapshotIds.length;
        uint supplyAt = 0;
        address[] memory tokens = new address[](numRewards);
        uint[] memory quantities = new uint[](numRewards);
        for (uint i = 0; i < numRewards; i++) {
            uint snapshotId = snapshotIds[i];
            supplyAt = totalSupplyAt(snapshotId);
            tokens[i] = rewardToken[snapshotId];
            quantities[i] = rewardQuantity[snapshotId]
                .mul(balanceOfAt(user, snapshotId))
                .div(supplyAt == 0 ? 1 : supplyAt);
        }
        return (tokens, quantities);
    }

    function getRewards(uint[] memory snapshotIds) public view returns (address[] memory, uint[] memory) {
        uint numRewards = snapshotIds.length;
        address[] memory tokens = new address[](numRewards);
        uint[] memory quantities = new uint[](numRewards);
        for (uint i = 0; i < numRewards; i++) {
            uint snapshotId = snapshotIds[i];
            tokens[i] = rewardToken[snapshotId];
            quantities[i] = rewardQuantity[snapshotId];
        }
        return (tokens, quantities);
    }

    function getCurrentSnapshotId() public view returns (uint) {
        return _getCurrentSnapshotId();
    }

    function getApp() external view returns (address) {
        return _app;
    }

    function getUser() external view returns (address) {
        return _user;
    }

    function getToken() external view returns (address) {
        return _token;
    }


    function hasClaimed(address user, uint snapshotId) public view returns (bool) {
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
