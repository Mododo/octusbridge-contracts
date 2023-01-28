// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.0;


import "../../interfaces/multivault/IMultiVaultFacetDeposit.sol";
import "../../interfaces/multivault/IMultiVaultFacetFees.sol";
import "../../interfaces/multivault/IMultiVaultFacetTokens.sol";
import "../../interfaces/multivault/IMultiVaultFacetPendingWithdrawals.sol";
import "../../interfaces/multivault/IMultiVaultFacetPendingWithdrawalsEvents.sol";
import "../../interfaces/IMultiVaultToken.sol";
import "../../interfaces/IEverscale.sol";
import "../../interfaces/IERC20.sol";
import "../../../interfaces/IWETH.sol";

import "../../libraries/SafeERC20.sol";

import "../storage/MultiVaultStorage.sol";

import "../helpers/MultiVaultHelperEverscale.sol";
import "../helpers/MultiVaultHelperReentrancyGuard.sol";
import "../helpers/MultiVaultHelperTokens.sol";
import "../helpers/MultiVaultHelperFee.sol";
import "../helpers/MultiVaultHelperPendingWithdrawal.sol";
import "hardhat/console.sol";



contract MultiVaultFacetDeposit is
    MultiVaultHelperFee,
    MultiVaultHelperEverscale,
    MultiVaultHelperReentrancyGuard,
    MultiVaultHelperTokens,
    MultiVaultHelperPendingWithdrawal,
    IMultiVaultFacetDeposit
{
    using SafeERC20 for IERC20;

    function depositByNativeToken(
        DepositNativeTokenParams memory d
    )
        external
        payable
        override
        nonReentrant
        wethNotBlacklisted
        initializeWethToken
        onlyEmergencyDisabled
    {
        require(msg.value >= d.amount, "WRONG");
        MultiVaultStorage.Storage storage s = MultiVaultStorage._storage();

        IWETH(s.weth).deposit{value: d.amount}();
        _deposit(
            DepositParams({
            recipient: d.recipient,
            token: s.weth,
            amount: d.amount,
            expected_evers: d.expected_evers,
            payload: d.payload
            }),
            address(this),
            msg.sender,
            msg.value - d.amount
        );
    }

    function deposit(
        DepositParams memory d
    )
        external
        payable
        override
        nonReentrant
        tokenNotBlacklisted(d.token)
        initializeToken(d.token)
        onlyEmergencyDisabled
    {
        _deposit(d, msg.sender, msg.sender, msg.value);
    }
    /// @notice Transfer tokens to the Everscale. Works both for native and alien tokens.
    /// Approve is required only for alien tokens deposit.
    /// @param d Deposit parameters
    function _deposit(
        DepositParams memory d,
        address _tokens_sender,
        address _original_sender,
        uint256 _value
    ) internal {
        MultiVaultStorage.Storage storage s = MultiVaultStorage._storage();
        uint fee = _calculateMovementFee(
            d.amount,
            d.token,
            IMultiVaultFacetFees.Fee.Deposit
        );

        bool isNative = s.tokens_[d.token].isNative;

        // Replace token address with custom token, if specified
        address token = s.tokens_[d.token].custom == address(0) ? d.token : s.tokens_[d.token].custom;

        if (isNative) {
            IMultiVaultToken(token).burn(
                _tokens_sender,
                d.amount
            );

            d.amount -= fee;

            _transferToEverscaleNative(d, fee, _value, _original_sender);
        } else {
            IERC20(token).safeTransferFrom(
                _tokens_sender,
                address(this),
                d.amount
            );

            d.amount -= fee;

            _transferToEverscaleAlien(d, fee, _value, _original_sender);
        }

        _increaseTokenFee(d.token, fee);
        _drainGas();
    }

    function depositByNativeToken(
        DepositNativeTokenParams memory d,
        uint256 expectedMinBounty,
        IMultiVaultFacetPendingWithdrawals.PendingWithdrawalId[] memory pendingWithdrawalIds
    ) external payable override wethNotBlacklisted nonReentrant {
        require(msg.value >= d.amount, "WRONG");
        MultiVaultStorage.Storage storage s = MultiVaultStorage._storage();

        IWETH(s.weth).deposit{value: d.amount}();
        _deposit(
            DepositParams({
                recipient:d.recipient,
                token: s.weth,
                amount: d.amount,
                expected_evers: d.expected_evers,
                payload: d.payload
            }),
            expectedMinBounty,
            pendingWithdrawalIds,
            msg.value - d.amount
        );
    }
    function deposit(
        DepositParams memory d,
        uint256 expectedMinBounty,
        IMultiVaultFacetPendingWithdrawals.PendingWithdrawalId[] memory pendingWithdrawalIds
    ) external payable override tokenNotBlacklisted(d.token) nonReentrant {
        _deposit(d, expectedMinBounty, pendingWithdrawalIds, msg.value);
    }
    function _deposit(
        DepositParams memory d,
        uint256 expectedMinBounty,
        IMultiVaultFacetPendingWithdrawals.PendingWithdrawalId[] memory pendingWithdrawalIds,
        uint256 _value
    ) internal {
        MultiVaultStorage.Storage storage s = MultiVaultStorage._storage();

        uint amountLeft = d.amount;
        uint amountPlusBounty = d.amount;

        IERC20(d.token).safeTransferFrom(msg.sender, address(this), d.amount);

        for (uint i = 0; i < pendingWithdrawalIds.length; i++) {
            IMultiVaultFacetPendingWithdrawals.PendingWithdrawalId memory pendingWithdrawalId = pendingWithdrawalIds[i];
            IMultiVaultFacetPendingWithdrawals.PendingWithdrawalParams memory pendingWithdrawal = _pendingWithdrawal(pendingWithdrawalId);

            require(pendingWithdrawal.amount > 0);
            require(pendingWithdrawal.token == d.token);

            amountLeft -= pendingWithdrawal.amount;
            amountPlusBounty += pendingWithdrawal.bounty;

            s.pendingWithdrawals_[pendingWithdrawalId.recipient][pendingWithdrawalId.id].amount = 0;

            emit PendingWithdrawalFill(
                pendingWithdrawalId.recipient,
                pendingWithdrawalId.id
            );

            IERC20(pendingWithdrawal.token).safeTransfer(
                pendingWithdrawalId.recipient,
                pendingWithdrawal.amount - pendingWithdrawal.bounty
            );
        }

        require(amountPlusBounty - d.amount >= expectedMinBounty);

        uint fee = _calculateMovementFee(d.amount, d.token, IMultiVaultFacetFees.Fee.Deposit);

        d.amount = amountPlusBounty - fee;

        _transferToEverscaleAlien(
            d,
            fee,
            _value,
            msg.sender
        );

        _increaseTokenFee(d.token, fee);

        _drainGas();
    }

    function _drainGas() internal {
        MultiVaultStorage.Storage storage s = MultiVaultStorage._storage();

        address payable gasDonor = payable(s.gasDonor);

        if (gasDonor != address(0)) {
            gasDonor.transfer(address(this).balance);
        }
    }
}
