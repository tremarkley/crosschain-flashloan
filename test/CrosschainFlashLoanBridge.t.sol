// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {CrosschainFlashLoanBridge} from "../src/CrosschainFlashLoanBridge.sol";
import {FlashLoanVault} from "../src/FlashLoanVault.sol";
import {CrosschainFlashLoanToken} from "../src/CrosschainFlashLoanToken.sol";
import {IERC20} from "@openzeppelin-contracts/interfaces/IERC20.sol";
import {ISuperchainTokenBridge} from "interop-lib/interfaces/ISuperchainTokenBridge.sol";
import {IL2ToL2CrossDomainMessenger} from "interop-lib/interfaces/IL2ToL2CrossDomainMessenger.sol";

contract CrosschainFlashLoanBridgeTest is Test {
    CrosschainFlashLoanBridge bridge;
    FlashLoanVault vault;
    CrosschainFlashLoanToken token;
    address constant MESSENGER = 0x4200000000000000000000000000000000000023;
    address constant SUPERCHAIN_BRIDGE = 0x4200000000000000000000000000000000000028;
    address owner = makeAddr("owner");
    address target = makeAddr("target");
    uint256 constant AMOUNT = 1000;
    uint256 constant FEE = 0.01 ether;

    function _mockAndExpect(address _receiver, bytes memory _calldata, bytes memory _returned) internal {
        vm.mockCall(_receiver, _calldata, _returned);
        vm.expectCall(_receiver, _calldata);
    }

    function setUp() public {
        // Deploy contracts
        token = new CrosschainFlashLoanToken(owner);
        vault = new FlashLoanVault();
        bridge = new CrosschainFlashLoanBridge(address(token), address(vault), FEE, owner);

        // Setup token balance
        vm.startPrank(owner);
        token.mint(address(bridge), AMOUNT);
        vm.stopPrank();
    }

    function test_InitiateCrosschainFlashLoan() public {
        // Mock bridge sendERC20 call
        _mockAndExpect(
            SUPERCHAIN_BRIDGE,
            abi.encodeCall(ISuperchainTokenBridge.sendERC20, (address(token), address(bridge), AMOUNT, 902)),
            abi.encode(bytes32(0))
        );

        // Mock messenger sendMessage call
        bytes memory message = abi.encodeWithSelector(
            CrosschainFlashLoanBridge.executeCrosschainFlashLoan.selector,
            token,
            address(this),
            AMOUNT,
            target,
            abi.encodeWithSelector(this.execute.selector)
        );
        _mockAndExpect(
            MESSENGER,
            abi.encodeCall(IL2ToL2CrossDomainMessenger.sendMessage, (902, address(bridge), message)),
            abi.encode(bytes32(0))
        );

        bridge.initiateCrosschainFlashLoan(902, AMOUNT, target, abi.encodeWithSelector(this.execute.selector));
    }

    function testFail_InsufficientFee() public {
        bridge.initiateCrosschainFlashLoan(902, AMOUNT, address(this), abi.encodeWithSelector(this.execute.selector));
    }

    function test_WithdrawFees() public {
        // Send a flash loan to accumulate fees
        // Mock bridge sendERC20 call
        _mockAndExpect(
            SUPERCHAIN_BRIDGE,
            abi.encodeCall(ISuperchainTokenBridge.sendERC20, (address(token), address(bridge), AMOUNT, 902)),
            abi.encode(bytes32(0))
        );

        // Mock messenger sendMessage call
        bytes memory message = abi.encodeWithSelector(
            CrosschainFlashLoanBridge.executeCrosschainFlashLoan.selector,
            token,
            address(this),
            AMOUNT,
            target,
            abi.encodeWithSelector(this.execute.selector)
        );
        _mockAndExpect(
            MESSENGER,
            abi.encodeCall(IL2ToL2CrossDomainMessenger.sendMessage, (902, address(bridge), message)),
            abi.encode(bytes32(0))
        );

        bridge.initiateCrosschainFlashLoan(902, AMOUNT, target, abi.encodeWithSelector(this.execute.selector));

        // Withdraw fees
        uint256 initialBalance = owner.balance;
        vm.prank(owner);
        bridge.withdrawFees();
        assertEq(owner.balance - initialBalance, FEE);
    }

    function testFail_UnauthorizedWithdraw() public {
        vm.prank(makeAddr("unauthorized"));
        bridge.withdrawFees();
    }

    function test_ExecuteCrosschainFlashLoan() public {
        // Setup token balances
        vm.startPrank(owner);
        token.mint(address(vault), AMOUNT);
        vm.stopPrank();

        // Approve vault to spend tokens
        vm.prank(address(bridge));
        token.approve(address(vault), AMOUNT);

        // Mock bridge sendERC20 call for return transfer
        _mockAndExpect(
            SUPERCHAIN_BRIDGE,
            abi.encodeCall(ISuperchainTokenBridge.sendERC20, (address(token), address(bridge), AMOUNT, block.chainid)),
            abi.encode(bytes32(0))
        );

        // Execute the flash loan
        vm.prank(MESSENGER);
        bridge.executeCrosschainFlashLoan(
            block.chainid, address(this), AMOUNT, target, abi.encodeWithSelector(this.execute.selector)
        );

        // Verify the tokens were sent back via the bridge
        assertEq(token.balanceOf(address(bridge)), AMOUNT);
    }

    function testInitiateAndExecuteCrosschainFlashLoan() public {
        // Setup: mint tokens for the bridge
        vm.startPrank(owner);
        token.mint(address(bridge), 1000);
        vm.stopPrank();

        // Mock bridge sendERC20 call
        _mockAndExpect(
            SUPERCHAIN_BRIDGE,
            abi.encodeCall(ISuperchainTokenBridge.sendERC20, (address(token), address(bridge), 1000, 902)),
            abi.encode(bytes32(0))
        );

        // Mock messenger sendMessage call
        bytes memory message = abi.encodeWithSelector(
            CrosschainFlashLoanBridge.executeCrosschainFlashLoan.selector,
            block.chainid,
            address(this),
            1000,
            target,
            abi.encodeWithSelector(this.execute.selector)
        );
        _mockAndExpect(
            MESSENGER,
            abi.encodeCall(IL2ToL2CrossDomainMessenger.sendMessage, (902, address(bridge), message)),
            abi.encode(bytes32(0))
        );

        // Call initiateAndExecuteCrosschainFlashLoan
        bridge.initiateAndExecuteCrosschainFlashLoan{value: FEE}(
            902, 1000, target, abi.encodeWithSelector(this.execute.selector)
        );
    }

    // Helper function to simulate target contract behavior
    function execute() external {
        // Do something with the borrowed tokens
        require(token.balanceOf(address(this)) > 0, "Did not receive tokens");

        // Always transfer tokens back to bridge
        token.transfer(address(bridge), token.balanceOf(address(this)));
    }
}
