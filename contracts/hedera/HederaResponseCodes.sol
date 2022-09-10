// SPDX-License-Identifier: Apache-2.0
pragma solidity =0.6.12;

abstract contract HederaResponseCodes {
    
    // response codes - check hedera hashgraph github repo for complete list
    int32 internal constant UNKNOWN = 21; // The responding node has submitted the transaction to the network. Its final status is still unknown.
    int32 internal constant SUCCESS = 22; // The transaction succeeded

}
