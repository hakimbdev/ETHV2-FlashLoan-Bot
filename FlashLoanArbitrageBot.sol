// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "https://github.com/openzeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";
import "https://github.com/aave/protocol-v2/blob/master/contracts/interfaces/ILendingPool.sol";
import "https://github.com/Uniswap/v2-periphery/blob/master/contracts/interfaces/IUniswapV2Router02.sol";
import "https://github.com/Uniswap/v2-core/blob/master/contracts/interfaces/IUniswapV2Factory.sol";

contract FlashLoanArbitrage {
    address private owner;
    address private constant AAVE_POOL = 0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9; // Replace with Aave Pool address
    address private constant UNISWAP_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D; // Replace with Uniswap router address
    address private constant SUSHISWAP_ROUTER = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F; // Replace with Sushiswap router address
    uint256 private constant MINIMUM_DEPOSIT = 0.001 ether;
    uint256 private constant MAX_FLASHLOAN_AMOUNT = 1000 ether;

    modifier onlyOwner() {
        require(msg.sender == owner, "Not the owner");
        _;
    }

    modifier meetsMinimumDeposit(uint256 amount) {
        require(amount >= MINIMUM_DEPOSIT, "Deposit amount too low");
        _;
    }

    modifier withinFlashLoanLimit(uint256 amount) {
        require(amount <= MAX_FLASHLOAN_AMOUNT, "Amount exceeds flash loan limit");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function executeArbitrage(
        address tokenBorrow,
        uint256 amount,
        address tokenSell,
        address tokenBuy
    ) external onlyOwner meetsMinimumDeposit(amount) withinFlashLoanLimit(amount) {
        IPool(AAVE_POOL).flashLoan(
            address(this),
            tokenBorrow,
            amount,
            abi.encode(tokenSell, tokenBuy)
        );
    }

    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    ) external returns (bool) {
        require(msg.sender == AAVE_POOL, "Invalid sender");
        require(initiator == address(this), "Invalid initiator");

        (address tokenSell, address tokenBuy) = abi.decode(params, (address, address));

        uint256 initialBalance = IERC20(asset).balanceOf(address(this));
        require(initialBalance >= amount, "Insufficient balance");

        // Approve Uniswap router
        IERC20(asset).approve(UNISWAP_ROUTER, amount);

        uint256 sellAmount = swapTokens(
            UNISWAP_ROUTER,
            tokenSell,
            tokenBuy,
            amount
        );

        // Approve Sushiswap router
        IERC20(tokenBuy).approve(SUSHISWAP_ROUTER, sellAmount);

        uint256 buyAmount = swapTokens(
            SUSHISWAP_ROUTER,
            tokenBuy,
            tokenSell,
            sellAmount
        );

        // Ensure profit covers premium
        require(buyAmount > amount + premium, "Arbitrage not profitable");

        // Repay loan
        IERC20(asset).approve(AAVE_POOL, amount + premium);

        return true;
    }

    function swapTokens(
        address router,
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal returns (uint256) {
        IUniswapV2Router02 swapRouter = IUniswapV2Router02(router);
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        uint256[] memory amounts = swapRouter.swapExactTokensForTokens(
            amountIn,
            1, // Accept any amount of tokenOut
            path,
            address(this),
            block.timestamp
        );

        return amounts[1];
    }

    function withdraw(address token) external onlyOwner {
        uint256 balance = IERC20(token).balanceOf(address(this));
        require(balance > 0, "No balance to withdraw");
        IERC20(token).transfer(owner, balance);
    }

    function kill() external onlyOwner {
        selfdestruct(payable(owner));
    }
}
