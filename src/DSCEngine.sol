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

contract DSDEngine {
    /* Errors */
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();

    /* State Variables */
    mapping(address token => address priceDFeed) private s_priceFeeds;     

    /* Modifiers */
    modifier moreThanZero(uint256 amount) {
        if (amount == 0){
            revert DSCEngine__NeedsMoreThanZero();
            _;
        }
    }

    // modifier isAllowedToken(address token) {}


     /* Functions */
    constructor(
        address[] memory tokenAddresses,
        address[] memory priceFeedAddresses,
        address dscAddress
    ) {
        if (tokenAddresses.length != priceFeedAddresses.length){
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }
        // For example ETH / USD, BTC / USD, MKR / USD
        for (uint256 i = 0; i < tokenAddresses.length; i++){
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
        }
    }

    /* External Functions */
    function depositCollateralAndMintDSC() external {}
    
    /**
     * 
     * @param tokenCollateralAddress The addrews of the token to deposit as collateral 
     * @param amountCollateral The amont of collateral to deposit
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral) external moreThanZero(amountCollateral) {

    }
    function redeeemCollateralForDSC() external {}
    function redeemCollateral() external {}
    function mintDSC() external {}
    function burnDSC() external {}
    
    // If someone pays back your minted DSC, they can have all your collateral for a discount
    function liquidate() external {}
    function getHealthFactor() external {}
}