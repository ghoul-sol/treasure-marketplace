// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ERC20Mintable is ERC20("MAGIC", "MAGIC") {
    function mint(address _to, uint256 _amount) public {
        _mint(_to, _amount);
    }
}
