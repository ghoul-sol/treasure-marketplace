// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// @dev This is an unused contract forcing ERC1967Proxy getting into the build,
//      so it can be used in the deployment scripts.
contract ForceERC1967Proxy is ERC1967Proxy {
    constructor(address implementation, bytes memory data) ERC1967Proxy(implementation, data) {}
}
