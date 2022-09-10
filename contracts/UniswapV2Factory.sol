// SPDX-License-Identifier: GPL-3.0

pragma solidity =0.6.12;

import './interfaces/IUniswapV2Factory.sol';
import './UniswapV2Pair.sol';
import './hedera/SafeHederaTokenService.sol';

contract UniswapV2Factory is IUniswapV2Factory, SafeHederaTokenService {
    
    bytes32 public constant INIT_CODE_PAIR_HASH = keccak256(abi.encodePacked(type(UniswapV2Pair).creationCode));
    address public override feeTo;
    address public override feeToSetter;
    address public override rentPayer;
    uint256 public override pairCreateFee;
    uint256 public tokenCreateFee;

    mapping(address => mapping(address => address)) public override getPair;
    address[] public override allPairs;

    event PairCreated(address indexed token0, address indexed token1, address pair, uint);

    constructor(address _feeToSetter, uint256 _pairCreateFee, uint256 _tokenCreateFee) public {
        feeToSetter = _feeToSetter;
        pairCreateFee = _pairCreateFee;
        tokenCreateFee = _tokenCreateFee;

        rentPayer = _feeToSetter;
    }

    function allPairsLength() external override view returns (uint) {
        return allPairs.length;
    }

    function createPair(address tokenA, address tokenB) 
        external payable costsTinycents(pairCreateFee) override returns (address pair) {
        require(tokenA != tokenB, 'UniswapV2: IDENTICAL_ADDRESSES');
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'UniswapV2: ZERO_ADDRESS');
        require(getPair[token0][token1] == address(0), 'UniswapV2: PAIR_EXISTS'); // single check is sufficient
        bytes memory bytecode = type(UniswapV2Pair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
            if iszero(extcodesize(pair)) {
                revert(0, 0)
            }            
        }
        UniswapV2Pair(pair).initialize(token0, token1);

        uint256 feeInTinybars = tinycentsToTinybars(tokenCreateFee);
        address lpToken = UniswapV2Pair(pair).createFungible{value: feeInTinybars}();

        safeAssociateToken(address(this), lpToken); // address(this) is the burn address for MINIMUM_LIQUIDITY

        if (feeTo != address(0)) safeAssociateToken(feeTo, lpToken);
            
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // populate mapping in the reverse direction
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair, allPairs.length);

        // send the rest to rent paying account
        (bool result, ) = rentPayer.call{value: (msg.value - feeInTinybars)}("");
        require(result, "rentPayer did not receive fee");
    }

    // setters
    function setFeeTo(address _feeTo) external onlyFeeToSetter override {
        feeTo = _feeTo;
    }

    function setRentPayer(address _rentPayer) external onlyFeeToSetter override {
        rentPayer = _rentPayer;
    }

    function setFeeToSetter(address _feeToSetter) external onlyFeeToSetter override {
        feeToSetter = _feeToSetter;
    }

    /**
    * @dev Set the pair create fee for creating new pairs
    *
    * only feetosetter account callable
    *
    * @param _pairCreateFee new pair create fee
    */
    function setPairCreateFee(uint256 _pairCreateFee) external onlyFeeToSetter override {
        pairCreateFee = _pairCreateFee;
    }

    /**
    * @dev Set the token create fee
    *
    * only feetosetter account callable
    *
    * @param _tokenCreateFee new token create fee
    */
    function setTokenCreateFee(uint256 _tokenCreateFee) external onlyFeeToSetter override {
        require(pairCreateFee >= _tokenCreateFee);
        tokenCreateFee = _tokenCreateFee;
    }

    modifier onlyFeeToSetter {
      require(msg.sender == feeToSetter, 'UniswapV2: FORBIDDEN');
      _;
   }
}