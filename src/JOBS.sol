// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

contract JOBS is ERC20Burnable {
    constructor() ERC20("Jobs", "JOBS") {
        _mint(msg.sender, 1000000000 * (1 ether));
    }
}
