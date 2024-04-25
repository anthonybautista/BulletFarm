// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.22;

/// @title Simple v2 pool interface
interface IPool {
    function totalSupply() external view returns (uint256);
    function balanceOf(address owner) external view returns (uint256);
    function getReserves() external view returns (uint112, uint112, uint32);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function transfer(address to, uint256 value) external returns (bool);
}