// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.6.12;

import './interfaces/IUniswapV2Router02WithFee.sol';
import './interfaces/IUniswapV2Factory.sol';
import './libraries/UniswapV2Library.sol';
import './libraries/TransferHelper.sol';
import './hedera/SafeHederaTokenService.sol';
import './libraries/SafeMath.sol';
import './interfaces/IERC20.sol';
import './interfaces/IWHBAR.sol';

contract UniswapV2Router02WithFee is IUniswapV2Router02WithFee, SafeHederaTokenService {
    using SafeMath for uint;

    // Factory address
    address public immutable override factory;

    // The contract address
    address public immutable override WHBAR; 
    // The token address
    address public immutable override whbar;
    // The fee collector
    address public override feeCollector;
    // The fee on output token in bips
    uint256 public override feeBips;
    // The contract owner - roles: associate tokens, set feeCollector, feeBips, owner
    address public override owner;

    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, 'UniswapV2Router: EXPIRED');
        _;
    }

    modifier onlyOwner {
        require (msg.sender == owner, 'UniswapV2Router: NOT_OWNER');
        _;
    }

    /**
    * @dev constructor
    * 
    * @param _factory factory address
    * @param _WHBAR address of WHBAR
    */
    constructor(address _factory, address _WHBAR, address _feeCollector, uint256 _feeBips) public {
        require(_feeBips <= 50, 'constr: fee bips');
        require(_factory != address(0), 'constr: factory');
        require(_feeCollector != address(0), 'constr: feeCollector');
        
        factory = _factory;
        WHBAR = _WHBAR;
        address _whbar = IWHBAR(_WHBAR).token();
        safeAssociateToken(address(this), _whbar);
        whbar = _whbar;
        feeCollector = _feeCollector;
        feeBips = _feeBips;
        owner = msg.sender;
    }

    function setOwner(address _owner) external override onlyOwner {
        require(_owner != address(0), 'UniswapV2Router: owner cannot be address(0)');
        owner = _owner;
    }

    function setFeeCollector(address _feeCollector) external override onlyOwner {
        require(_feeCollector != address(0), 'UniswapV2Router: feeCollector cannot be address(0)');
        feeCollector = _feeCollector;
    }

    function setFeeBips(uint256 _feeBips) external override onlyOwner {
        require(_feeBips <= 50, 'UniswapV2Router: bips cannot exceed 50');
        feeBips = _feeBips;
    }

    function associateTokens(address[] calldata tokens) external override onlyOwner {
        safeAssociateTokens(address(this), tokens);
    }

    function dissociateTokens(address token) external override onlyOwner {
        safeDissociateToken(address(this), token);
    }

    // **** SWAP ****
    function _swap(uint[] memory amounts, address[] memory path, address _to) internal virtual {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = UniswapV2Library.sortTokens(input, output);
            uint amountOut = amounts[i + 1];
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOut) : (amountOut, uint(0));
            address to = i < path.length - 2 ? UniswapV2Library.pairFor(factory, output, path[i + 2]) : _to;
            IUniswapV2Pair(UniswapV2Library.pairFor(factory, input, output)).swap(
                amount0Out, amount1Out, to, new bytes(0)
            );
        }
    }

    function _sweepTokenWithFee(uint256 _amount, address _token, address _to) internal virtual {
        uint256 fee = _amount.mul(feeBips) / 10_000;

        safeTransferToken(
            _token, address(this), feeCollector, fee
        );

        emit FeeTransfer(_token, feeCollector, fee);
        if (_token == whbar) {
            safeApproveToken(whbar, WHBAR, _amount.sub(fee));       
            IWHBAR(WHBAR).withdraw(address(this), _to, _amount.sub(fee));
        } else {
            safeTransferToken(
                _token, address(this), _to, _amount.sub(fee)
            );
        }
    }

    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) returns (uint[] memory amounts) {
        amounts = UniswapV2Library.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT');

        safeTransferToken(
            path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, address(this));
        _sweepTokenWithFee(amounts[amounts.length - 1], path[path.length - 1], to);
    }
    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) returns (uint[] memory amounts) {
        amounts = UniswapV2Library.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, 'UniswapV2Router: EXCESSIVE_INPUT_AMOUNT');

        safeTransferToken(
            path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, address(this));
        _sweepTokenWithFee(amounts[amounts.length - 1], path[path.length - 1], to);
    }
 
    function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        virtual
        override
        payable
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[0] == whbar, 'UniswapV2Router: INVALID_PATH');
        amounts = UniswapV2Library.getAmountsOut(factory, msg.value, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT');
        IWHBAR(WHBAR).deposit{value: amounts[0]}(msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]));
        _swap(amounts, path, address(this));
        _sweepTokenWithFee(amounts[amounts.length - 1], path[path.length - 1], to);
    }

    function swapTokensForExactETH(uint amountOut, uint amountInMax, address[] calldata path, address to, uint deadline)
        external
        virtual
        override
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[path.length - 1] == whbar, 'UniswapV2Router: INVALID_PATH');
        amounts = UniswapV2Library.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, 'UniswapV2Router: EXCESSIVE_INPUT_AMOUNT');
        safeTransferToken(
            path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]
        );
        
        _swap(amounts, path, address(this));
        _sweepTokenWithFee(amounts[amounts.length - 1], path[path.length - 1], to);
    }
    function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        virtual
        override
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[path.length - 1] == whbar, 'UniswapV2Router: INVALID_PATH');
        amounts = UniswapV2Library.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT');

        safeTransferToken(
            path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]
        );

        _swap(amounts, path, address(this));
        _sweepTokenWithFee(amounts[amounts.length - 1], path[path.length - 1], to);
    }

    function swapETHForExactTokens(uint amountOut, address[] calldata path, address to, uint deadline)
        external
        virtual
        override
        payable
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[0] == whbar, 'UniswapV2Router: INVALID_PATH');
        amounts = UniswapV2Library.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= msg.value, 'UniswapV2Router: EXCESSIVE_INPUT_AMOUNT');
        IWHBAR(WHBAR).deposit{value: amounts[0]}(msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]));
        _swap(amounts, path, address(this));
        _sweepTokenWithFee(amounts[amounts.length - 1], path[path.length - 1], to);
        if (msg.value > amounts[0]) TransferHelper.safeTransferETH(msg.sender, msg.value - amounts[0]);
    }

    function _swapSupportingFeeOnTransferTokens(address[] memory path, address _to) internal virtual {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = UniswapV2Library.sortTokens(input, output);
            IUniswapV2Pair pair = IUniswapV2Pair(UniswapV2Library.pairFor(factory, input, output));
            uint amountInput;
            uint amountOutput;
            { // scope to avoid stack too deep errors
            (uint reserve0, uint reserve1,) = pair.getReserves();
            (uint reserveInput, uint reserveOutput) = input == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
            amountInput = IERC20(input).balanceOf(address(pair)).sub(reserveInput);
            amountOutput = UniswapV2Library.getAmountOut(amountInput, reserveInput, reserveOutput);
            }
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOutput) : (amountOutput, uint(0));
            address to = i < path.length - 2 ? UniswapV2Library.pairFor(factory, output, path[i + 2]) : _to;
            pair.swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }

    function _sweepTokenWithFeeSupportingFeeOnTransferTokens(address _token, address _to) internal virtual {
        uint256 _amount = IERC20(_token).balanceOf(address(this));
        uint256 fee = _amount.mul(feeBips) / 10_000;

        safeTransferToken(
            _token, address(this), feeCollector, fee
        );

        safeTransferToken(
            _token, address(this), _to, _amount.sub(fee)
        );
    }

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) {
        
        safeTransferToken(
            path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amountIn
        );
        uint balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, address(this));
        _sweepTokenWithFeeSupportingFeeOnTransferTokens(path[path.length - 1], to);
        // check amountOutMin after because two fee-on-transfer assessments can be unpleasant to user
        require(
            IERC20(path[path.length - 1]).balanceOf(to).sub(balanceBefore) >= amountOutMin,
            'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT'
        );
    }
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    )
        external
        virtual
        override
        payable
        ensure(deadline)
    {
        require(path[0] == whbar, 'UniswapV2Router: INVALID_PATH');
        uint amountIn = msg.value;
        IWHBAR(WHBAR).deposit{value: amountIn}(msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]));
        uint balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, address(this));
        _sweepTokenWithFeeSupportingFeeOnTransferTokens(path[path.length - 1], to);
        // check amountOutMin after because two fee-on-transfer assessments can be unpleasant to user
        require(
            IERC20(path[path.length - 1]).balanceOf(to).sub(balanceBefore) >= amountOutMin,
            'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT'
        );
    }
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    )
        external
        virtual
        override
        ensure(deadline)
    {
        require(path[path.length - 1] == whbar, 'UniswapV2Router: INVALID_PATH');
        uint startAmount = IERC20(whbar).balanceOf(address(this));
        safeTransferToken(
            path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amountIn
        );
        _swapSupportingFeeOnTransferTokens(path, address(this));
        uint endAmount = IERC20(whbar).balanceOf(address(this));
        uint amountOut = endAmount.sub(startAmount);
        require(amountOut >= amountOutMin, 'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT');
        _sweepTokenWithFee(amountOut, path[path.length - 1], to); // output is whbar
    }

    // **** LIBRARY FUNCTIONS **** apply fee to the resulting outputs (exactIn) or inputs (exactOut)
    function quote(uint amountA, uint reserveA, uint reserveB) public pure virtual override returns (uint256) {
        return UniswapV2Library.quote(amountA, reserveA, reserveB);
    }

    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut)
        public
        pure
        virtual
        override
        returns (uint amountOut)
    {
        return UniswapV2Library.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut)
        public
        pure
        virtual
        override
        returns (uint amountIn)
    {
        return UniswapV2Library.getAmountIn(amountOut, reserveIn, reserveOut);
    }

    function getAmountsOut(uint amountIn, address[] memory path)
        public
        view
        virtual
        override
        returns (uint[] memory amounts)
    {
        return UniswapV2Library.getAmountsOut(factory, amountIn, path);
    }

    function getAmountsIn(uint amountOut, address[] memory path)
        public
        view
        virtual
        override
        returns (uint[] memory amounts)
    {
        return UniswapV2Library.getAmountsIn(factory, amountOut, path);
    }
}
