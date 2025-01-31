// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {FlashLoanVault} from "../src/FlashLoanVault.sol";
import {CrosschainFlashLoanToken} from "../src/CrosschainFlashLoanToken.sol";
import {IERC20} from "@openzeppelin-contracts/interfaces/IERC20.sol";

contract MockBorrower {
    IERC20 public token;
    FlashLoanVault public vault;

    constructor(address _token, address _vault) {
        token = IERC20(_token);
        vault = FlashLoanVault(_vault);
    }

    function execute() external {
        // Do something with the borrowed tokens here
        require(token.balanceOf(address(this)) > 0, "Did not receive tokens");

        // Always transfer tokens back to vault - this is a flash loan!
        token.transfer(address(vault), token.balanceOf(address(this)));
    }
}

contract FlashLoanVaultTest is Test {
    FlashLoanVault vault;
    CrosschainFlashLoanToken token;
    MockBorrower borrower;
    address owner = makeAddr("owner");
    uint256 constant AMOUNT = 1000;
    uint256 constant TIMEOUT = 1 hours;

    function setUp() public {
        // Deploy token and vault
        token = new CrosschainFlashLoanToken(owner);
        vault = new FlashLoanVault();
        borrower = new MockBorrower(address(token), address(vault));

        // Setup token balances
        vm.startPrank(owner);
        token.mint(owner, AMOUNT);
        token.approve(address(vault), AMOUNT);
        vm.stopPrank();
    }

    function test_CreateLoan() public {
        vm.startPrank(owner);
        bytes32 loanId = vault.createLoan(address(token), AMOUNT, address(borrower), TIMEOUT);

        (
            address loanToken,
            uint256 loanAmount,
            address loanOwner,
            address loanBorrower,
            uint256 loanTimeout,
            bool isActive
        ) = vault.loans(loanId);

        assertEq(loanToken, address(token));
        assertEq(loanAmount, AMOUNT);
        assertEq(loanOwner, owner);
        assertEq(loanBorrower, address(borrower));
        assertEq(loanTimeout, block.timestamp + TIMEOUT);
        assertTrue(isActive);
        assertEq(token.balanceOf(address(vault)), AMOUNT);
    }

    function test_ExecuteFlashLoan() public {
        vm.startPrank(owner);
        bytes32 loanId = vault.createLoan(address(token), AMOUNT, address(borrower), TIMEOUT);
        vm.stopPrank();

        vm.startPrank(address(borrower));
        vault.executeFlashLoan(loanId, address(borrower), abi.encodeWithSelector(MockBorrower.execute.selector));
        assertEq(token.balanceOf(owner), AMOUNT);
        vm.stopPrank();
    }

    function test_ReclaimExpiredLoan() public {
        vm.startPrank(owner);
        bytes32 loanId = vault.createLoan(address(token), AMOUNT, address(borrower), TIMEOUT);
        vm.stopPrank();

        // Move time forward past timeout
        vm.warp(block.timestamp + TIMEOUT + 1);

        // Anyone can reclaim after timeout
        address reclaimer = makeAddr("reclaimer");
        vm.startPrank(reclaimer);
        vault.reclaimExpiredLoan(loanId);
        assertEq(token.balanceOf(owner), AMOUNT);
        vm.stopPrank();
    }

    function testFail_ExecuteAfterTimeout() public {
        vm.startPrank(owner);
        bytes32 loanId = vault.createLoan(address(token), AMOUNT, address(borrower), TIMEOUT);
        vm.stopPrank();

        // Move time forward past timeout
        vm.warp(block.timestamp + TIMEOUT + 1);

        vm.startPrank(address(borrower));
        vault.executeFlashLoan(loanId, address(borrower), abi.encodeWithSelector(MockBorrower.execute.selector));
    }

    function testFail_ReclaimBeforeTimeout() public {
        vm.startPrank(owner);
        bytes32 loanId = vault.createLoan(address(token), AMOUNT, address(borrower), TIMEOUT);
        vm.stopPrank();

        // Try to reclaim before timeout
        address reclaimer = makeAddr("reclaimer");
        vm.startPrank(reclaimer);
        vault.reclaimExpiredLoan(loanId);
    }

    function testFail_UnauthorizedExecute() public {
        vm.startPrank(owner);
        bytes32 loanId = vault.createLoan(address(token), AMOUNT, address(borrower), TIMEOUT);
        vm.stopPrank();

        // Try to execute from unauthorized address
        vm.startPrank(makeAddr("unauthorized"));
        vault.executeFlashLoan(loanId, address(borrower), abi.encodeWithSelector(MockBorrower.execute.selector));
    }
}
