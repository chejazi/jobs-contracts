// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./Splitter.sol";

contract Registry is Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;

    address private immutable _splitterTemplate;
    mapping(address => address) private _userSplitter;
    mapping(address => string) private _userBio;
    EnumerableSet.AddressSet private _users;
    EnumerableSet.AddressSet private _splitters;
    EnumerableSet.AddressSet private _registrars;

    modifier onlyRegistrar {
        require(isRegistrar(msg.sender), "Not a registrar");
        _;
    }

    constructor() {
        Splitter template = new Splitter(address(this));
        template.init(address(this));

        _splitterTemplate = address(template);
    }

    function _register(address user, string memory bio) internal returns (address) {
        address splitter = _userSplitter[user];
        if (splitter == address(0)) {
            splitter = Clones.cloneDeterministic(_splitterTemplate, keccak256(abi.encode(user)));
            Splitter(splitter).init(user);
            _userSplitter[user] = splitter;
            _userBio[user] = bio;
            _users.add(user);
            _splitters.add(splitter);
        }
        return splitter;
    }

    function rewardStakers(address stakedUser, address stakedToken, address rewardToken, uint rewardQuantity) external {
        address splitter = _userSplitter[stakedUser];
        require(splitter != address(0), "User not registered");
        require(
            IERC20(rewardToken).transferFrom(msg.sender, splitter, rewardQuantity),
            "Unable to transfer token"
        );
        Splitter(splitter).split(stakedToken, rewardToken, rewardQuantity);
    }

    function autoRegister(address user) external onlyRegistrar {
        _register(user, "");
    }
    function register(string memory bio) external {
        _register(msg.sender, bio);
    }
    function update(string memory bio) external {
        _register(msg.sender, bio);
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

    function getSplitters() external view returns (address[] memory) {
        return _splitters.values();
    }
    function getSplitterAt(uint index) external view returns (address) {
        return _splitters.at(index);
    }
    function getNumSplitters() external view returns (uint) {
        return _splitters.length();
    }
    function isSplitter(address app) external view returns (bool) {
        return _splitters.contains(app);
    }

    function getSplitter(address user) external view returns (address) {
        return _userSplitter[user];
    }

    function getBio(address user) external view returns (string memory) {
        return _userBio[user];
    }
}
