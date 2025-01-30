// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";
import {CrosschainFlashLoanToken} from "../src/CrosschainFlashLoanToken.sol";
import {PredeployAddresses} from "interop-lib/libraries/PredeployAddresses.sol";
import {IERC7802} from "interop-lib/interfaces/IERC7802.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract CrosschainFlashLoanTokenTest is Test {
    CrosschainFlashLoanToken token;
    address owner;
    address user1;
    address user2;

    function setUp() public {
        owner = makeAddr("owner");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        
        // Deploy token with owner
        vm.prank(owner);
        token = new CrosschainFlashLoanToken(owner);
    }

    // Basic token info tests
    function test_TokenInfo() public view {
        assertEq(token.name(), "XChainFlashLoan");
        assertEq(token.symbol(), "CXL");
        assertEq(token.decimals(), 18);
    }

    // Ownership tests
    function test_OnlyOwnerCanMint() public {
        vm.prank(owner);
        token.mint(user1, 100);
        assertEq(token.balanceOf(user1), 100);

        // Non-owner should not be able to mint
        vm.prank(user1);
        vm.expectRevert();
        token.mint(user1, 100);
    }

    function test_OnlyOwnerCanBurn() public {
        // Setup: mint some tokens first
        vm.prank(owner);
        token.mint(user1, 100);

        // Non-owner should not be able to burn
        vm.prank(user1);
        vm.expectRevert();
        token.burn(user1, 50);

        // Owner should be able to burn
        vm.prank(owner);
        token.burn(user1, 50);
        assertEq(token.balanceOf(user1), 50);
    }

    // Cross-chain functionality tests
    function test_CrosschainMint() public {
        // Only SuperchainTokenBridge should be able to crosschain mint
        vm.prank(PredeployAddresses.SUPERCHAIN_TOKEN_BRIDGE);
        token.crosschainMint(user1, 100);
        assertEq(token.balanceOf(user1), 100);

        // Other addresses should not be able to crosschain mint
        vm.prank(user2);
        vm.expectRevert("Unauthorized");
        token.crosschainMint(user1, 100);
    }

    function test_CrosschainBurn() public {
        // Setup: mint some tokens first
        vm.prank(PredeployAddresses.SUPERCHAIN_TOKEN_BRIDGE);
        token.crosschainMint(user1, 100);

        // Only SuperchainTokenBridge should be able to crosschain burn
        vm.prank(PredeployAddresses.SUPERCHAIN_TOKEN_BRIDGE);
        token.crosschainBurn(user1, 50);
        assertEq(token.balanceOf(user1), 50);

        // Other addresses should not be able to crosschain burn
        vm.prank(user2);
        vm.expectRevert("Unauthorized");
        token.crosschainBurn(user1, 50);
    }

    // ERC20 functionality tests
    function test_Transfer() public {
        // Setup: mint some tokens
        vm.prank(owner);
        token.mint(user1, 100);

        // Test transfer
        vm.prank(user1);
        token.transfer(user2, 50);
        assertEq(token.balanceOf(user1), 50);
        assertEq(token.balanceOf(user2), 50);
    }

    function test_TransferFrom() public {
        // Setup: mint some tokens
        vm.prank(owner);
        token.mint(user1, 100);

        // Approve user2 to spend user1's tokens
        vm.prank(user1);
        token.approve(user2, 50);

        // Test transferFrom
        vm.prank(user2);
        token.transferFrom(user1, user2, 50);
        assertEq(token.balanceOf(user1), 50);
        assertEq(token.balanceOf(user2), 50);
    }

    // Interface support tests
    function test_SupportsInterfaces() public view {
        assertTrue(token.supportsInterface(type(IERC7802).interfaceId));
        assertTrue(token.supportsInterface(type(IERC20).interfaceId));
        assertTrue(token.supportsInterface(type(IERC165).interfaceId));
    }

    // Edge cases and failure tests
    function test_CannotTransferMoreThanBalance() public {
        vm.prank(owner);
        token.mint(user1, 100);

        vm.prank(user1);
        vm.expectRevert();
        token.transfer(user2, 101);
    }

    function test_CannotBurnMoreThanBalance() public {
        vm.prank(owner);
        token.mint(user1, 100);

        vm.prank(owner);
        vm.expectRevert();
        token.burn(user1, 101);
    }

    function test_CannotTransferFromWithoutAllowance() public {
        vm.prank(owner);
        token.mint(user1, 100);

        vm.prank(user2);
        vm.expectRevert();
        token.transferFrom(user1, user2, 50);
    }
} 