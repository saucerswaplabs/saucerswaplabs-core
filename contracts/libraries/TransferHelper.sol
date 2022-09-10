// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.6.12;

library TransferHelper {

    function safeTransferETH(address to, uint value) internal {
        (bool success,) = to.call{value:value}(new bytes(0));
        require(success, 'TransferHelper: ETH_TRANSFER_FAILED');
    }
}