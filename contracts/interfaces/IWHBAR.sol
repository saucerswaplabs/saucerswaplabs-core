// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.6.12;

interface IWHBAR {
    function token() external returns (address);
    function deposit() external payable;
    function deposit(address src, address dst) external payable;
    function withdraw(address src, address dst, uint wad) external;
    function withdraw(uint wad) external;

    event  Deposit(address indexed dst, uint wad);
    event  Withdrawal(address indexed src, uint wad);   
}
