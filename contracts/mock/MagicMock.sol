// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MagicMock is ERC20("MAGIC Mock", "MAGIC") {
    function mint(address _to, uint256 _amount) public {
        _mint(_to, _amount);
    }
}
