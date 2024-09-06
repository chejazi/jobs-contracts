// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Snapshot.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "./Stakers.sol";

interface Rebased {
    function onStake(address user, address token, uint quantity) external;
    function onUnstake(address user, address token, uint quantity) external;
}

contract UserApp is Rebased {
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;

    address private constant _rebase = 0x89fA20b30a88811FBB044821FEC130793185c60B;
    address private immutable _stakersTemplate;
    address private _user;
    address private _directory;
    mapping(address => address) private _stakers;
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
        _stakersTemplate = address(new Stakers(address(this), user, address(0)));
        _user = user;
        _directory = msg.sender;
    }

    function init(address user) external {
        require(_user == address(0), "Cannot reinitialize");
        _user = user;
        _directory = msg.sender;
    }

    function onStake(address user, address token, uint quantity) external onlyRebase {
        address stakers = _getOrCreateStakers(token);
        Stakers(stakers).add(user, quantity);
    }

    function onUnstake(address user, address token, uint quantity) external onlyRebase {
        address stakers = _getOrCreateStakers(token);
        Stakers(stakers).remove(user, quantity);
    }

    function rewardStakers(address stakedToken, address rewardToken, uint quantity) external onlyDirectory {
        address stakers = _getOrCreateStakers(stakedToken);
        Stakers(stakers).reward(rewardToken, quantity);
    }

    function claim(address to, address[] memory stakedTokens, uint[][] memory snapshots) external {
        for (uint n = 0; n < stakedTokens.length; n++) {
            (address[] memory rewardTokens, uint[] memory quantities) = Stakers(stakedTokens[n]).claim(msg.sender, snapshots[n]);

            for (uint i = 0; i < rewardTokens.length; i++) {
                if (quantities[i] > 0) {
                    try ERC20(rewardTokens[i]).transfer(to, quantities[i]) {}
                    catch {}
                }
            }
        }
    }

    function _getOrCreateStakers(address token) internal returns (address) {
        address stakers = _stakers[token];
        if (stakers == address(0)) {
            stakers = Clones.cloneDeterministic(_stakersTemplate, bytes32(uint(uint160(_user) ^ uint160(token))));
            Stakers(stakers).init(address(this), _user, token);
        }
        return stakers;
    }

    function getRewards(address user, address[] memory stakedTokens, uint[][] memory snapshots) public view returns (address[][] memory, uint[][] memory) {
        uint numStakes = stakedTokens.length;
        address[][] memory rewardTokens = new address[][](numStakes);
        uint[][] memory quantities = new uint[][](numStakes);
        for (uint i = 0; i < numStakes; i++) {
            (rewardTokens[i], quantities[i]) = Stakers(stakedTokens[i]).getUserRewards(user, snapshots[i]);
        }
        return (rewardTokens, quantities);
    }

    function getUser() external view returns (address) {
        return _user;
    }

    function getStakers(address token) external view returns (address) {
        return _stakers[token];
    }
}
