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

    function testFuzz_DepositAccounting(uint96 amount) public {
        vm.assume(amount > 0);
        vm.deal(alice, amount);
        vm.prank(alice);
        vault.deposit{value: amount}();
        assertEq(vault.balanceOf(alice) + vault.collectedFees(), amount);
    }
}
