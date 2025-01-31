// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {SuperchainERC20} from "./SuperchainERC20.sol";
import {Ownable} from "solady/src/auth/Ownable.sol";

contract CrosschainFlashLoanToken is SuperchainERC20, Ownable {
    string private constant _name = "XChainFlashLoan";
    string private constant _symbol = "CXL";
    uint8 private constant _decimals = 18;

    constructor(address owner_) {
        _initializeOwner(owner_);
    }

    function name() public pure override returns (string memory) {
        return _name;
    }

    function symbol() public pure override returns (string memory) {
        return _symbol;
    }

    function decimals() public pure override returns (uint8) {
        return _decimals;
    }

    function mint(address to_, uint256 amount_) external onlyOwner {
        _mint(to_, amount_);
    }

    function burn(address from_, uint256 amount_) external onlyOwner {
        _burn(from_, amount_);
    }
}
