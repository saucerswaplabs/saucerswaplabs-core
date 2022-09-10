// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.6.12;

import './interfaces/IUniswapV2Router02.sol';
import './interfaces/IUniswapV2Factory.sol';
import './libraries/UniswapV2Library.sol';
import './libraries/TransferHelper.sol';
import './hedera/SafeHederaTokenService.sol';
import './libraries/SafeMath.sol';
import './interfaces/IERC20.sol';
import './interfaces/IWHBAR.sol';

contract UniswapV2Router02 is IUniswapV2Router02, SafeHederaTokenService {
    using SafeMath for uint;

    // Factory address
    address public immutable override factory;

    // The contract address
    address public immutable override WHBAR; 
    // The token address
    address public immutable override whbar;

    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, 'UniswapV2Router: EXPIRED');
        _;
    }

    function getBlock() public view returns(uint256 _block) {
        _block = block.number;
    }

    /**
    * @dev constructor
    * 
    * @param _factory factory address
    * @param _WHBAR address of WHBAR
    */
    constructor(address _factory, address _WHBAR) public {
        factory = _factory;
        WHBAR = _WHBAR;
        whbar = IWHBAR(_WHBAR).token();
    }

    // **** ADD LIQUIDITY ****
    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin
    ) internal virtual view returns (uint amountA, uint amountB) {
        (uint reserveA, uint reserveB) = UniswapV2Library.getReserves(factory, tokenA, tokenB);
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint amountBOptimal = UniswapV2Library.quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, 'UniswapV2Router: INSUFFICIENT_B_AMOUNT');
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint amountAOptimal = UniswapV2Library.quote(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired);
                require(amountAOptimal >= amountAMin, 'UniswapV2Router: INSUFFICIENT_A_AMOUNT');
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    /**
    * @dev Create the pool with two tokens if it doesn't exist and add liquidity.  The lp token is associated to the account 
    * and the tokens are transfered to the pair contract in order to mint said LP token.
    * 
    * @param tokenA token A address
    * @param tokenB token B address
    * @param amountADesired desired output amount of token A
    * @param amountBDesired desired output amount of token B
    * @param amountAMin minimum amount of token A
    * @param amountBMin minimum amount of token B
    * @param to recipient address
    * @param deadline time stamp of deadline
    * 
    * @return amountA amount of token A out
    * @return amountB amount of token B out 
    * @return liquidity minted liquidity
    */
    function addLiquidityNewPool(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external virtual payable override ensure(deadline) returns (uint amountA, uint amountB, uint liquidity) {
        require (IUniswapV2Factory(factory).getPair(tokenA, tokenB) == address(0), "UniswapV2Router: POOL ALREADY EXISTS");
        address pair = IUniswapV2Factory(factory).createPair{value: msg.value}(tokenA, tokenB);
        
        safeAssociateToken(to, IUniswapV2Pair(pair).lpToken());
        (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);

        safeTransferToken(
            tokenA, msg.sender, pair, amountA
        );
        safeTransferToken(
            tokenB, msg.sender, pair, amountB
        );
        liquidity = IUniswapV2Pair(pair).mint(to);
    }
    

    /**
    * @dev Create the pool with a token and whbar if it doesn't exist and add liquidity. The lp token is associated to the account 
    * and the token and whbar are transfered to the pair contract in order to mint said LP token,
    *
    * @param token token address
    * @param amountTokenDesired desired output amount of token
    * @param amountTokenMin minimum amount of token A
    * @param amountETHMin minimum amount of token B
    * @param to recipient address
    * @param deadline time stamp of deadline
    * 
    * @return amountToken amount of token out
    * @return amountETH amount of eth out
    * @return liquidity minted liquidity 
    */
    function addLiquidityETHNewPool(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external virtual payable override ensure(deadline) returns (uint amountToken, uint amountETH, uint liquidity) {
        require (IUniswapV2Factory(factory).getPair(token, whbar) == address(0), "UniswapV2Router: POOL ALREADY EXISTS");
        uint256 feeInTinybars = tinycentsToTinybars(IUniswapV2Factory(factory).pairCreateFee());

        address addr = IUniswapV2Factory(factory).createPair{value: feeInTinybars}(token, whbar);
        safeAssociateToken(to, IUniswapV2Pair(addr).lpToken());

        (amountToken, amountETH) = _addLiquidity(token, whbar, amountTokenDesired, msg.value - feeInTinybars, amountTokenMin, amountETHMin);
        address pair = UniswapV2Library.pairFor(factory, token, whbar);
        
        safeTransferTokenRouter(
            token, msg.sender, pair, amountToken
        );
        IWHBAR(WHBAR).deposit{value: amountETH}(msg.sender, pair);
        liquidity = IUniswapV2Pair(pair).mint(to);
        if (msg.value - feeInTinybars > amountETH) TransferHelper.safeTransferETH(msg.sender, msg.value - feeInTinybars - amountETH);
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) returns (uint amountA, uint amountB, uint liquidity) {
        require(IUniswapV2Factory(factory).getPair(tokenA, tokenB) != address(0), "UniswapV2Router: PAIR DOES NOT EXIST");
        (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
        address pair = UniswapV2Library.pairFor(factory, tokenA, tokenB);
        
        safeTransferTokenRouter(
            tokenA, msg.sender, pair, amountA
        );
        safeTransferTokenRouter(
            tokenB, msg.sender, pair, amountB
        );
        liquidity = IUniswapV2Pair(pair).mint(to);
    }

    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external virtual override payable ensure(deadline) returns (uint amountToken, uint amountETH, uint liquidity) {
        require(IUniswapV2Factory(factory).getPair(token, whbar) != address(0), "UniswapV2Router: PAIR DOES NOT EXIST");
        (amountToken, amountETH) = _addLiquidity(
            token,
            whbar,
            amountTokenDesired,
            msg.value,
            amountTokenMin,
            amountETHMin
        );
        
        address pair = UniswapV2Library.pairFor(factory, token, whbar);

        safeTransferTokenRouter(
            token, msg.sender, pair, amountToken
        );
        IWHBAR(WHBAR).deposit{value: amountETH}(msg.sender, pair);
        liquidity = IUniswapV2Pair(pair).mint(to);
        // refund dust eth, if any
        if (msg.value > amountETH) TransferHelper.safeTransferETH(msg.sender, msg.value - amountETH);
    }

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) public virtual override ensure(deadline) returns (uint amountA, uint amountB) {
        address pair = UniswapV2Library.pairFor(factory, tokenA, tokenB);
        address lpToken = IUniswapV2Pair(pair).lpToken();
        safeTransferTokenRouter(
            lpToken, msg.sender, pair, liquidity
        );
        (uint amount0, uint amount1) = IUniswapV2Pair(pair).burn(to);
        (address token0,) = UniswapV2Library.sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
        require(amountA >= amountAMin, 'UniswapV2Router: INSUFFICIENT_A_AMOUNT');
        require(amountB >= amountBMin, 'UniswapV2Router: INSUFFICIENT_B_AMOUNT');
    }

    function removeLiquidityETH(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) public virtual override ensure(deadline) returns (uint amountToken, uint amountETH) {
        (amountToken, amountETH) = removeLiquidity( 
            token,
            whbar, 
            liquidity,
            amountTokenMin,
            amountETHMin,
            msg.sender,
            deadline
        );
        IWHBAR(WHBAR).withdraw(msg.sender, to, amountETH);
    }

    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) public virtual override ensure(deadline) returns (uint amountETH) {
        (, amountETH) = removeLiquidity(
            token,
            whbar, 
            liquidity,
            amountTokenMin,
            amountETHMin,
            msg.sender,
            deadline
        );
        IWHBAR(WHBAR).withdraw(msg.sender, to, amountETH);
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
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) returns (uint[] memory amounts) {
        amounts = UniswapV2Library.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT');

        safeTransferTokenRouter(
            path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, to);
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

        safeTransferTokenRouter(
            path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, to);
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
        _swap(amounts, path, to);
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

        safeTransferTokenRouter(
            path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]
        );
        
        _swap(amounts, path, to);       
        IWHBAR(WHBAR).withdraw(msg.sender, to, amounts[amounts.length - 1]);
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

        safeTransferTokenRouter(
            path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]
        );
         _swap(amounts, path, to);       
        IWHBAR(WHBAR).withdraw(msg.sender, to, amounts[amounts.length - 1]);
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
        _swap(amounts, path, to);
        // refund dust eth, if any
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
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) {
        
        safeTransferTokenRouter(
            path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amountIn
        );
        uint balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
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
        _swapSupportingFeeOnTransferTokens(path, to);
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
        uint startAmount = IERC20(whbar).balanceOf(msg.sender);
        safeTransferTokenRouter(
            path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amountIn
        );
        _swapSupportingFeeOnTransferTokens(path, msg.sender);
        uint endAmount = IERC20(whbar).balanceOf(msg.sender);
        uint amountOut = endAmount.sub(startAmount);
        require(amountOut >= amountOutMin, 'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT');
        IWHBAR(WHBAR).withdraw(msg.sender, to, amountOut);
    }

    // **** LIBRARY FUNCTIONS ****
    function quote(uint amountA, uint reserveA, uint reserveB) public pure virtual override returns (uint amountB) {
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
