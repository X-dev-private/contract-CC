// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {FeeVault} from "./FeeVault.sol";

contract FeeVaultTest is Test {
    FeeVault vault;
    address alice = address(0xA11CE);
    address treasury = address(0x7EA5);

    // permite que este contrato (owner) receba ETH
    receive() external payable {}

    function setUp() public {
        vault = new FeeVault(100); // 1%
        vm.deal(alice, 10 ether);
    }

    function test_DepositKeepsFee() public {
        vm.prank(alice);
        vault.deposit{value: 1 ether}();

        assertEq(vault.collectedFees(), 0.01 ether);
        assertEq(vault.balanceOf(alice), 0.99 ether);
        assertEq(address(vault).balance, 1 ether);
    }

    function test_ReceiveCountsAsDeposit() public {
        vm.prank(alice);
        (bool ok, ) = address(vault).call{value: 2 ether}("");
        assertTrue(ok);
        assertEq(vault.balanceOf(alice), 1.98 ether);
        assertEq(vault.collectedFees(), 0.02 ether);
    }

    function test_UserWithdraw() public {
        vm.startPrank(alice);
        vault.deposit{value: 1 ether}();
        vault.withdraw(0.99 ether);
        vm.stopPrank();

        assertEq(vault.balanceOf(alice), 0);
        assertEq(alice.balance, 9.99 ether);
        assertEq(address(vault).balance, 0.01 ether);
    }

    function test_WithdrawMoreThanBalanceReverts() public {
        vm.startPrank(alice);
        vault.deposit{value: 1 ether}();
        vm.expectRevert(FeeVault.InsufficientBalance.selector);
        vault.withdraw(1 ether);
        vm.stopPrank();
    }

    function test_OwnerWithdrawsFees() public {
        vm.prank(alice);
        vault.deposit{value: 1 ether}();

        vault.withdrawFees(payable(treasury));
        assertEq(treasury.balance, 0.01 ether);
        assertEq(vault.collectedFees(), 0);
    }

    function test_NonOwnerCannotWithdrawFees() public {
        vm.prank(alice);
        vm.expectRevert(FeeVault.NotOwner.selector);
        vault.withdrawFees(payable(alice));
    }

    function test_FeeCap() public {
        vm.expectRevert(FeeVault.FeeTooHigh.selector);
        vault.setFeeBps(501);
    }

    // ---------------- cara ou coroa ----------------

    address bob = address(0xB0B);

    function _fundBoth() internal {
        vm.deal(bob, 10 ether);
        vm.prank(alice);
        vault.deposit{value: 1 ether}(); // 0.99 de saldo
        vm.prank(bob);
        vault.deposit{value: 1 ether}(); // 0.99 de saldo
    }

    function test_BetFullFlow() public {
        _fundBoth();

        vm.prank(alice);
        uint256 id = vault.createBet(0.5 ether, FeeVault.Side.Cara);
        assertEq(vault.balanceOf(alice), 0.49 ether);

        vm.prank(bob);
        vault.joinBet(id);
        assertEq(vault.balanceOf(bob), 0.49 ether);

        vm.expectRevert(FeeVault.TooEarly.selector);
        vault.resolveBet(id);

        vm.roll(block.number + 2);
        vault.resolveBet(id);

        (, , , , , , address winner, ) = vault.bets(id);
        assertTrue(winner == alice || winner == bob);
        assertEq(vault.balanceOf(winner), 0.49 ether + 1 ether);
        // nada some: saldos + taxas == ETH no contrato
        assertEq(
            vault.balanceOf(alice) + vault.balanceOf(bob) + vault.collectedFees(),
            address(vault).balance
        );
    }

    function test_BetRefundAfterWindow() public {
        _fundBoth();
        vm.prank(alice);
        uint256 id = vault.createBet(0.5 ether, FeeVault.Side.Coroa);
        vm.prank(bob);
        vault.joinBet(id);

        vm.roll(block.number + 300);
        vault.resolveBet(id);

        assertEq(vault.balanceOf(alice), 0.99 ether);
        assertEq(vault.balanceOf(bob), 0.99 ether);
    }

    function test_CancelOpenBet() public {
        _fundBoth();
        vm.startPrank(alice);
        uint256 id = vault.createBet(0.5 ether, FeeVault.Side.Cara);
        vault.cancelBet(id);
        vm.stopPrank();
        assertEq(vault.balanceOf(alice), 0.99 ether);

        vm.prank(bob);
        vm.expectRevert(FeeVault.BetNotOpen.selector);
        vault.joinBet(id);
    }

    function test_CannotBetMoreThanBalance() public {
        _fundBoth();
        vm.prank(alice);
        vm.expectRevert(FeeVault.InsufficientBalance.selector);
        vault.createBet(1 ether, FeeVault.Side.Cara);
    }

    function test_CannotJoinOwnBet() public {
        _fundBoth();
        vm.startPrank(alice);
        uint256 id = vault.createBet(0.1 ether, FeeVault.Side.Cara);
        vm.expectRevert(FeeVault.CannotJoinOwnBet.selector);
        vault.joinBet(id);
        vm.stopPrank();
    }

    function test_OnlyCreatorCancels() public {
        _fundBoth();
        vm.prank(alice);
        uint256 id = vault.createBet(0.1 ether, FeeVault.Side.Cara);
        vm.prank(bob);
        vm.expectRevert(FeeVault.NotBetCreator.selector);
        vault.cancelBet(id);
    }

    function _resolvedBet() internal returns (uint256 id, address winner, address loser) {
        _fundBoth();
        vm.prank(alice);
        id = vault.createBet(0.5 ether, FeeVault.Side.Cara);
        vm.prank(bob);
        vault.joinBet(id);
        vm.roll(block.number + 2);
        vault.resolveBet(id);
        (, , , , , , winner, ) = vault.bets(id);
        loser = winner == alice ? bob : alice;
    }

    function test_WinnerReturnsAll() public {
        (uint256 id, address winner, address loser) = _resolvedBet();
        vm.prank(winner);
        vault.returnToLoser(id, 0.5 ether);
        // os dois voltam ao saldo de antes da aposta
        assertEq(vault.balanceOf(winner), 0.99 ether);
        assertEq(vault.balanceOf(loser), 0.99 ether);
    }

    function test_WinnerReturnsInParts() public {
        (uint256 id, address winner, address loser) = _resolvedBet();
        vm.startPrank(winner);
        vault.returnToLoser(id, 0.2 ether);
        vault.returnToLoser(id, 0.3 ether);
        vm.expectRevert(FeeVault.ReturnTooHigh.selector);
        vault.returnToLoser(id, 1);
        vm.stopPrank();
        assertEq(vault.balanceOf(loser), 0.49 ether + 0.5 ether);
    }

    function test_OnlyWinnerReturns() public {
        (uint256 id, , address loser) = _resolvedBet();
        vm.prank(loser);
        vm.expectRevert(FeeVault.NotBetWinner.selector);
        vault.returnToLoser(id, 0.1 ether);
    }

    function test_CannotReturnBeforeResolve() public {
        _fundBoth();
        vm.prank(alice);
        uint256 id = vault.createBet(0.5 ether, FeeVault.Side.Cara);
        vm.prank(bob);
        vault.joinBet(id);
        vm.prank(alice);
        vm.expectRevert(FeeVault.BetNotResolved.selector);
        vault.returnToLoser(id, 0.1 ether);
    }

    function testFuzz_DepositAccounting(uint96 amount) public {
        vm.assume(amount > 0);
        vm.deal(alice, amount);
        vm.prank(alice);
        vault.deposit{value: amount}();
        assertEq(vault.balanceOf(alice) + vault.collectedFees(), amount);
    }
}
