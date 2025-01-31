// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20} from "@openzeppelin-contracts/interfaces/IERC20.sol";
import {FlashLoanVault} from "./FlashLoanVault.sol";
import {CrosschainFlashLoanToken} from "./CrosschainFlashLoanToken.sol";
import {ISuperchainTokenBridge} from "interop-lib/interfaces/ISuperchainTokenBridge.sol";
import {IL2ToL2CrossDomainMessenger} from "interop-lib/interfaces/IL2ToL2CrossDomainMessenger.sol";
import {AsyncEnabled} from "superchain-async/AsyncEnabled.sol";

interface RemoteCrosschainFlashLoanBridge {
    function asyncJustReturnArgumentsBack(uint256, address, uint256, address, bytes memory)
        external
        returns (CrosschainFlashLoanPromise);
}

interface CrosschainFlashLoanPromise {
    function then(function(uint256, address, uint256, address, bytes memory) external) external;
}

/// @title CrosschainFlashLoanBridge
/// @notice A contract that facilitates cross-chain flash loans using FlashLoanVault
contract CrosschainFlashLoanBridge is AsyncEnabled {
    // The token used for flash loans
    CrosschainFlashLoanToken public immutable token;
    // The vault on this chain
    FlashLoanVault public immutable vault;
    // The bridge for cross-chain transfers
    ISuperchainTokenBridge public constant bridge = ISuperchainTokenBridge(0x4200000000000000000000000000000000000028);
    // The messenger for cross-chain messages
    IL2ToL2CrossDomainMessenger public constant messenger =
        IL2ToL2CrossDomainMessenger(0x4200000000000000000000000000000000000023);
    // Fee charged for cross-chain flash loans
    uint256 public immutable flatFee;
    // Owner who can withdraw fees
    address public immutable owner;

    event CrosschainFlashLoanInitiated(
        uint256 indexed destinationChain, address indexed borrower, uint256 amount, uint256 fee
    );

    event CrosschainFlashLoanCompleted(uint256 indexed sourceChain, address indexed borrower, uint256 amount);

    error InsufficientFee();
    error TransferFailed();
    error CallFailed();

    constructor(address _token, address _vault, uint256 _flatFee, address _owner) {
        token = CrosschainFlashLoanToken(_token);
        vault = FlashLoanVault(_vault);
        flatFee = _flatFee;
        owner = _owner;
    }

    /// @notice Initiates a cross-chain flash loan
    /// @param destinationChain The chain ID where the flash loan will be executed
    /// @param amount The amount to borrow
    /// @param target The contract to call on the destination chain
    /// @param data The calldata to execute on the target contract
    function initiateCrosschainFlashLoan(uint256 destinationChain, uint256 amount, address target, bytes calldata data)
        external
        payable
    {
        // Check that sufficient fee was paid
        if (msg.value < flatFee) revert InsufficientFee();

        // Approve bridge to transfer tokens
        token.approve(address(bridge), amount);

        // Send tokens to destination chain
        bridge.sendERC20(address(token), address(this), amount, destinationChain);

        RemoteCrosschainFlashLoanBridge remote =
            RemoteCrosschainFlashLoanBridge(getAsyncProxy(address(this), destinationChain));
        CrosschainFlashLoanPromise initiateFlashLoanPromise =
            remote.asyncJustReturnArgumentsBack(destinationChain, msg.sender, amount, target, data);
        // send message to the destination chain to execute the flash loan
        initiateFlashLoanPromise.then(this.asyncSendExecuteCrosschainFlashLoanToDestinationChain);
    }

    function asyncJustReturnArgumentsBack(
        uint256 sourceChain,
        address borrower,
        uint256 amount,
        address target,
        bytes memory data
    ) external async returns (uint256, address, uint256, address, bytes memory) {
        return (sourceChain, borrower, amount, target, data);
    }

    function asyncSendExecuteCrosschainFlashLoanToDestinationChain(
        uint256 destinationChain,
        address borrower,
        uint256 amount,
        address target,
        bytes memory data
    ) external asyncCallback {
        messenger.sendMessage(
            destinationChain,
            address(this),
            abi.encodeWithSelector(
                this.executeCrosschainFlashLoan.selector, block.chainid, borrower, amount, target, data
            )
        );
    }

    /// @notice Executes the flash loan on the destination chain and returns tokens
    /// @param sourceChain The chain ID where the flash loan was initiated
    /// @param borrower The address that initiated the flash loan
    /// @param amount The amount to borrow
    /// @param target The contract to call with the borrowed funds
    /// @param data The calldata to execute on the target contract
    function executeCrosschainFlashLoan(
        uint256 sourceChain,
        address borrower,
        uint256 amount,
        address target,
        bytes memory data
    ) external {
        require(msg.sender == address(messenger), "Unauthorized");

        // give approval to the vault to transfer tokens
        token.approve(address(vault), amount);

        // Create flash loan
        bytes32 loanId = vault.createLoan(
            address(token),
            amount,
            address(this),
            1 hours // Long timeout since we need to wait for cross-chain messages
        );

        // Execute flash loan
        vault.executeFlashLoan(loanId, target, data);

        // Send tokens back to this contract on source chain
        bridge.sendERC20(
            address(token),
            address(this), // Send back to this contract on source chain
            amount,
            sourceChain
        );

        emit CrosschainFlashLoanCompleted(sourceChain, borrower, amount);
    }

    /// @notice Allows owner to withdraw accumulated fees
    function withdrawFees() external {
        require(msg.sender == owner, "Not authorized");
        (bool success,) = owner.call{value: address(this).balance}("");
        if (!success) revert TransferFailed();
    }
}
