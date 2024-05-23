// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

// import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Test, console} from "forge-std/Test.sol";
// import { ERC20Mock } from "@openzeppelin/contracts/mocks/ERC20Mock.sol"; Updated mock location
import { ERC20Mock } from "../mocks/ERC20Mock.sol";

import { MockV3Aggregator } from "../mocks/MockV3Aggregator.sol";
import { DSCEngine, AggregatorV3Interface } from "../../src/DSCEngine.sol";
import { DecentralizedStableCoin } from "../../src/DecentralizedStableCoin.sol";
import { MockV3Aggregator } from "../mocks/MockV3Aggregator.sol";

contract Handler is Test {
    // Deployed contracts to interact with
    DSCEngine public engine;
    DecentralizedStableCoin public dsc;
    // MockV3Aggregator public ethUsdPriceFeed;
    // MockV3Aggregator public btcUsdPriceFeed;
    ERC20Mock public weth;
    ERC20Mock public wbtc;

    uint256 public timesMintIsCalled;
    address[] public usersWithCollateralDeposited;

    // Ghost Variables
    uint96 public constant MAX_DEPOSIT_SIZE = type(uint96).max;

    constructor(DSCEngine _dscEngine, DecentralizedStableCoin _dsc) {
        engine = _dscEngine;
        dsc = _dsc;

        address[] memory collateralTokens = engine.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);

        // ethUsdPriceFeed = MockV3Aggregator(engine.getCollateralTokenPriceFeed(address(weth)));
        // btcUsdPriceFeed = MockV3Aggregator(engine.getCollateralTokenPriceFeed(address(wbtc)));
    }


     function mintDsc(uint256 amount, uint256 addressSeed) public {
        if (usersWithCollateralDeposited.length == 0) {
            return;
        }
        address sender = usersWithCollateralDeposited[addressSeed % usersWithCollateralDeposited.length];
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(sender);
        int256 maxDscToMint = int256(collateralValueInUsd / 2) - int256(totalDscMinted);

        if (maxDscToMint < 0) {
            return;
        }
        amount = bound(amount, 0, uint256(maxDscToMint));
        if (amount == 0) {
            return;
        }
        vm.startPrank(sender);

        engine.mintDSC(amount);
        vm.stopPrank();
        timesMintIsCalled++;
     }
     
     
     // FUNCTOINS TO INTERACT WITH

    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
    ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
    amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);

    vm.startPrank(msg.sender);
    collateral.mint(msg.sender, amountCollateral);
    collateral.approve(address(engine), amountCollateral);
    engine.depositCollateral(address(collateral), amountCollateral);
    vm.stopPrank();
    // double push 
    usersWithCollateralDeposited.push(msg.sender);
}

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxCollateralToRedeem = engine.getCollateralBalanceOfUser(msg.sender, address(collateral));
        
        amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem);

        if (amountCollateral == 0) {
            return;
        }
        // vm.prank(msg.sender);
        engine.redeemCollateral(address(collateral), amountCollateral);
    }

    // Helper functions
    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock)
    {
        if (collateralSeed % 2 == 0) {
            return weth;
        }
        return wbtc;
    }
}

