// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "./StakePool.sol";

interface Rebased {
    function onStake(address user, address token, uint quantity) external;
    function onUnstake(address user, address token, uint quantity) external;
}

contract UserApp is Rebased {
    using EnumerableSet for EnumerableSet.AddressSet;

    address private constant _rebase = 0x89fA20b30a88811FBB044821FEC130793185c60B;
    address private immutable _stakePoolTemplate;
    address private _user;
    address private _directory;
    mapping(address => address) private _stakePool;
    mapping(address => EnumerableSet.AddressSet) private _userBlocks;
    mapping(address => EnumerableSet.AddressSet) private _userStakes;

    modifier onlyRebase {
        require(msg.sender == _rebase, "Only Rebase");
        _;
    }

    modifier onlyDirectory {
        require(msg.sender == _directory, "Only Directory");
        _;
    }

    constructor(address user) {
        _stakePoolTemplate = address(new StakePool(address(this), user, address(0)));
        _user = user;
        _directory = msg.sender;
    }

    function init(address user) external {
        require(_user == address(0), "Cannot reinitialize");
        _user = user;
        _directory = msg.sender;
    }

    function onStake(address user, address token, uint quantity) external onlyRebase {
        address stakePool = _getOrCreateStakePool(token);
        StakePool(stakePool).add(user, quantity);
    }

    function onUnstake(address user, address token, uint quantity) external onlyRebase {
        address stakePool = _getOrCreateStakePool(token);
        StakePool(stakePool).remove(user, quantity);
    }

    function rewardStakers(address stakedToken, address rewardToken, uint quantity) external onlyDirectory {
        address stakePool = _getOrCreateStakePool(stakedToken);
        StakePool(stakePool).reward(rewardToken, quantity);
    }

    function claim(address to, address[] memory stakedTokens, uint[][] memory snapshots) external {
        for (uint n = 0; n < stakedTokens.length; n++) {
            (address[] memory rewardTokens, uint[] memory quantities) = StakePool(stakedTokens[n]).claim(msg.sender, snapshots[n]);

            for (uint i = 0; i < rewardTokens.length; i++) {
                if (quantities[i] > 0) {
                    require(
                        IERC20(rewardTokens[i]).transfer(to, quantities[i]),
                        "Unable to claim tokens"
                    );
                }
            }
        }
    }

    function _getOrCreateStakePool(address token) internal returns (address) {
        address stakePool = _stakePool[token];
        if (stakePool == address(0)) {
            stakePool = Clones.cloneDeterministic(_stakePoolTemplate, bytes32(uint(uint160(_user) ^ uint160(token))));
            StakePool(stakePool).init(address(this), _user, token);
        }
        return stakePool;
    }

    function getRewards(address user, address[] memory stakedTokens, uint[][] memory snapshots) public view returns (address[][] memory, uint[][] memory) {
        uint numStakes = stakedTokens.length;
        address[][] memory rewardTokens = new address[][](numStakes);
        uint[][] memory quantities = new uint[][](numStakes);
        for (uint i = 0; i < numStakes; i++) {
            (rewardTokens[i], quantities[i]) = StakePool(stakedTokens[i]).getUserRewards(user, snapshots[i]);
        }
        return (rewardTokens, quantities);
    }

    function getUser() external view returns (address) {
        return _user;
    }

    function getStakePool(address token) external view returns (address) {
        return _stakePool[token];
    }
}
