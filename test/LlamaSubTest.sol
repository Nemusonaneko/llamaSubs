// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {LlamaSubsFlatRateERC20} from "../src/LlamaSubsFlatRateERC20.sol";
import {LlamaToken} from "./LlamaToken.sol";

contract LlamaSubTest is Test {
    LlamaSubsFlatRateERC20 public llamasub;
    LlamaToken public token;

    address public immutable alice = address(1);
    address public immutable alice2 = address(2);
    address public immutable alice3 = address(3);
    address public immutable alice4 = address(4);
    address public immutable alice5 = address(5);
    address public immutable alice6 = address(6);
    address public immutable alice7 = address(7);
    address public immutable alice8 = address(8);
    address public immutable alice9 = address(9);
    address public immutable alice10 = address(10);

    function setUp() external {
        vm.warp(0);
        token = new LlamaToken();
        llamasub = new LlamaSubsFlatRateERC20(alice, address(token), 0, 86400);
        token.mint(alice, 10000000e18);
        token.mint(alice2, 10000000e18);
        token.mint(alice3, 10000000e18);
        token.mint(alice4, 10000000e18);
        token.mint(alice5, 10000000e18);
        token.mint(alice6, 10000000e18);
        token.mint(alice7, 10000000e18);
        token.mint(alice8, 10000000e18);
        token.mint(alice9, 10000000e18);
        token.mint(alice10, 10000000e18);
        vm.prank(alice);
        token.approve(address(llamasub), 10000000e18);
        vm.prank(alice2);
        token.approve(address(llamasub), 10000000e18);
        vm.prank(alice3);
        token.approve(address(llamasub), 10000000e18);
        vm.prank(alice4);
        token.approve(address(llamasub), 10000000e18);
        vm.prank(alice5);
        token.approve(address(llamasub), 10000000e18);
        vm.prank(alice6);
        token.approve(address(llamasub), 10000000e18);
        vm.prank(alice7);
        token.approve(address(llamasub), 10000000e18);
        vm.prank(alice8);
        token.approve(address(llamasub), 10000000e18);
        vm.prank(alice9);
        token.approve(address(llamasub), 10000000e18);
        vm.prank(alice10);
        token.approve(address(llamasub), 10000000e18);
        vm.startPrank(alice);
        llamasub.addTier(1e18);
        llamasub.addTier(2e18);
        vm.stopPrank();
    }

    function testSub() external {
        vm.startPrank(alice);
        llamasub.subscribe(address(alice), 0, 3);
        vm.stopPrank();
        (uint216 tier, uint40 expires) = llamasub.users(alice);
        assertEq(tier, 0);
        assertEq(expires, 86400 * 2);
    }

    function testClaim() external {
        vm.warp(86400 * 4);
        vm.prank(alice);
        llamasub.claim(100000);
    }
}
