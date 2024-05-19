// SPDX-License-Identifier: MIT

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions


pragma solidity ^0.8.19;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title DSCEngine
 * @author Luca Liebenberg
 * 
 * The system is designed to be as miniaml as possible, and have the tokens maintain a 1 token == $1 peg.
 * This stablecoin has the properties:
 * - Exogneous Collateral
 * - Dollar Pegged
 * - Algorithmically Stable
 * 
 * It is similar to DAI if DAI had no governance, no feees, and was only backed by wETH and wBTC.
 * 
 * Our DSC system should always be "overcollateralized". 
 * At no point, should the value of all collateral <= thr $ backed value of all the DSC.
 * 
 * @notice This contract is the core of the DSC System. It handles all the lgoic for mining and redeeming DSC, as well as depositing & withdrawing collateral.
 * @notice This contract is VERY looseklt based on the MakerDAO DSS (DAI) system.
 */

contract DSCEngine is ReentrancyGuard {
    /* Errors */
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();

    /* State Variables */
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 150->200% over collateralized
    uint256 private constant LIQUIDATION_PRECISION = 100; 
    uint256 private constant LIQUIDATION_BONUS = 10; // this represents a 10% bonus
    uint256 private constant MIN_HEALTH_FACTOR = 1e18; 

    
    mapping(address token => address priceDFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;
    address[] private s_collateralTokens;


    DecentralizedStableCoin private immutable i_dsc;

    /* Events */
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount);

    /* Modifiers */
    modifier moreThanZero(uint256 amount) {
        if (amount == 0){
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
       _;
    }


     /* Functions */
    constructor(
        address[] memory tokenAddresses,
        address[] memory priceFeedAddresses,
        address dscAddress
    ) {
        // USD Price Feeds
        if (tokenAddresses.length != priceFeedAddresses.length){
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }
        // For example ETH / USD, BTC / USD, MKR / USD
        for (uint256 i = 0; i < tokenAddresses.length; i++){
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    /* External Functions */

    /**
     * @notice this function will deposit your collateral, and mint DSC in one transaction
     * @param tokenCollateralAddress The address of the token to deposit as collateral  
     * @param amountCollateral The amont of collateral to deposit
     * @param amountDscToMint The amont of decentralized stablecoin to deposit
     */
    function depositCollateralAndMintDSC(
        address tokenCollateralAddress, 
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDSC(amountDscToMint);
    }
    
    /**
     * @notice follows CEI
     * @param tokenCollateralAddress The address of the token to deposit as collateral  
     * @param amountCollateral The amont of collateral to deposit
     */
    function depositCollateral(
        address tokenCollateralAddress, 
        uint256 amountCollateral
        ) 
        public 
        moreThanZero(amountCollateral) 
        isAllowedToken(tokenCollateralAddress)
        nonReentrant 
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success){
            revert DSCEngine__TransferFailed();
        }
    }
    
    /**
     * @notice This fucntion burns DSC and redeems underlying collateral in one transaction
     * @param tokenCollateralAddress The address of the token to deposit as collateral  
     * @param amountCollateral The amont of collateral to deposit
     * @param amountDscToBurn The amont of decentralized token to burn
     */
    function redeemCollateralForDSC
    (
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToBurn
    ) 
    external 
    {
        burnDSC(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        // redeemCollateral already checks health factor
    }
    
    // CEI: Checks, Effects, Interactons
    /* Health factor must be over 1 AFTER collateral pulled */
    function redeemCollateral
    (
        address tokenCollateralAddress,
        uint256 amountCollateral,
        address from,
        address to
    ) 
    public
    moreThanZero(amountCollateral)
    nonReentrant
    {
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }
    
     /**
     * @notice follows CEI
     * @param amountDscToMint The amount of decentralized stablecoin to mint
     * @notice they must have more collateral value than the minimum threshold
     */
    function mintDSC(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint;
        // if they minted too much 
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }
    
    
    function burnDSC
    (
        uint256 amount
    ) 
    public 
    moreThanZero(amount) 
    {
       _burnDsc(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender); // This will probably never hit...
    }
    
    // If someone pays back your minted DSC, they can have all your collateral for a discount
    // If someone is almost undercollateralized, we will pay you to liquidate them
    
    /**
     * 
     * @param collateral The ERC20 collateral address to liquidate from the user
     * @param user The user who has broken the health factor. Their _healthFactor should be below
     *  MIN_HEALTH_FACTOR 
     * @param debtToCover The amount of DSC you want to burn to improve the users health factor
     * @notice You can partially liquidate a user
     * @notice You will get a liquidation bonus for taking the users funds
     * @notice This function working assumes the protocol will be roughly 200%
     * over collateralized in order for this to work
     * @notice A known bug would be if the protocol were 100% or less collateralized, then
     * we wouldn't be able to incentiize the liquidators
     * 
     * Follows CEI: Checks, Effects, Interactions
     */
    function liquidate
    (
        address collateral, 
        address user, 
        uint256 debtToCover
    ) 
    external
    moreThanZero(debtToCover)
    nonReentrant 
    {
        // check health factor of the user
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR){
            revert DSCEngine__HealthFactorOk();
        }
        // we want to burn the DSC "debt"
        // and take their collateral
        // Bad user: $140 ETH, $100 DSC ( debtToCover -> $100)
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);

        // give the liquidator a 10% bonus
        // implement a feature to liquidate in the event of the protocol is insolvent
        // sweep extra amounts into a treasury
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;
        _redeemCollateral(collateral, totalCollateralToRedeem, user, msg.sender);
        
        // We need to burn the DSC
        _burnDsc(debtToCover, user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor){
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }
    function getHealthFactor() external {}


    /* Private & Internal functions */

    /**
     * 
     * @dev Low-level internal function, do not call unless the function calling it
     * is checking for health factors being broken
     */
    function _burnDsc(uint256 amountDscToBurn, address onBehalfOf, address dscFrom) private {
        s_DSCMinted[onBehalfOf] -= amountDscToBurn;
        bool success = i_dsc.transferFrom(msg.sender, address(this), amountDscToBurn);
        // This conditional is hypothetically unreachable
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDscToBurn);
    }

    function _redeemCollateral
    (
        address tokenCollateralAddress,
         uint256 amountCollateral,
         address from, 
         address to 
    )
    private 
    {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);

        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success){
            revert DSCEngine__TransferFailed();
        }
    }
    
    function _getAccountInformation(address user) 
    private 
    view 
    returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
     totalDscMinted = s_DSCMinted[user];
     collateralValueInUsd = _getAccountCollateralValueInUsd(user);   
    }
    
    /**
     * 
     * Retruns how close to liquidation a user is
     * If a user goes below 1, they can get liquidated
     */
    function _healthFactor(address user) private view  returns (uint256) {
        // total DSC minted
        // total colalteral VALUE
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }
    
    // 1. Check health factor (do they have enough collateral)
    // 2. Revert if they do not
    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    /* Public & External Functions */

    function getTokenAmountFromUsd
    (
        address token, 
        uint256 usdAmountInWei
    ) 
    public view 
    returns(uint256)  
    {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        // ($10e18 * 1e18) / ($2000e8 * 1e10)
        return (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function _getAccountCollateralValueInUsd(address user) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (,int256 price,,,) = priceFeed.latestRoundData();

        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION; // (1000 * 1e8 * (1e10)) * 1000 * 1e18;
    }
}