// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./UserApp.sol";

contract UserAppDirectory is Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;

    address private immutable _userAppTemplate;
    mapping(address => address) private _userApp;
    mapping(address => string) private _userBio;
    EnumerableSet.AddressSet private _users;
    EnumerableSet.AddressSet private _registrars;

    modifier onlyRegistrar {
        require(isRegistrar(msg.sender), "Not a registrar");
        _;
    }

    constructor() {
        UserApp template = new UserApp(address(this));
        template.init(address(this));

        _userAppTemplate = address(template);
    }

    function _register(address user, string memory bio) internal returns (address) {
        address userApp = _userApp[user];
        if (userApp == address(0)) {
            userApp = Clones.cloneDeterministic(_userAppTemplate, bytes32(uint(uint160(user))));
            UserApp(userApp).init(user);
            _userApp[user] = userApp;
            _userBio[user] = bio;
            _users.add(user);
        }
        return userApp;
    }

    function rewardUserStakers(address user, address stakedToken, address rewardToken, uint quantity) external {
        address userApp = _userApp[user];
        require(userApp != address(0), "User not registered");
        require(
            IERC20(rewardToken).transferFrom(msg.sender, userApp, quantity),
            "Unable to transfer token"
        );
        UserApp(userApp).rewardStakers(stakedToken, rewardToken, quantity);
    }

    function autoRegister(address user) external onlyRegistrar {
        _register(user, "");
    }
    function register(string memory bio) external {
        _register(msg.sender, bio);
    }
    function update(string memory bio) external {
        _userBio[msg.sender] = bio;
    }

    function addRegistrar(address registrar) external onlyOwner {
        _registrars.add(registrar);
    }
    function removeRegistrar(address registrar) external onlyOwner {
        _registrars.remove(registrar);
    }
    function isRegistrar(address registrar) public view returns (bool) {
        return _registrars.contains(registrar);
    }
    function getRegistrars() external view returns (address[] memory) {
        return _registrars.values();
    }
    function getRegistrarAt(uint index) external view returns (address) {
        return _registrars.at(index);
    }
    function getNumRegistrars() external view returns (uint) {
        return _registrars.length();
    }

    function getUsers() external view returns (address[] memory) {
        return _users.values();
    }
    function getUserAt(uint index) external view returns (address) {
        return _users.at(index);
    }
    function getNumUsers() external view returns (uint) {
        return _users.length();
    }
    function isUser(address user) external view returns (bool) {
        return _users.contains(user);
    }

    function getApp(address user) external view returns (address) {
        return _userApp[user];
    }
    function getApps(address[] memory users) external view returns (address[] memory) {
        address[] memory apps = new address[](users.length);
        for (uint i = 0; i < users.length; i++) {
            apps[i] = _userApp[users[i]];
        }
        return apps;
    }

    function getBio(address user) external view returns (string memory) {
        return _userBio[user];
    }
    function getBios(address[] memory users) external view returns (string[] memory) {
        string[] memory bios = new string[](users.length);
        for (uint i = 0; i < users.length; i++) {
            bios[i] = _userBio[users[i]];
        }
        return bios;
    }
}
