// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";

contract Top50Tokens {
    address public owner;
    address public usdcTokenAddress;
    address public uniswapV2FactoryAddress;
    address public uniswapV3FactoryAddress;
    address public nonfungiblePositionManagerAddress;

    struct TokenData {
        address token;
        uint256 usdValue;
    }

    mapping(address => bool) public isTokenInTop50;
    TokenData[] public topTokens;

    constructor(
        address _usdcTokenAddress,
        address _uniswapV2FactoryAddress,
        address _uniswapV3FactoryAddress,
        address _nonfungiblePositionManagerAddress
    ) {
        owner = msg.sender;
        usdcTokenAddress = _usdcTokenAddress;
        uniswapV2FactoryAddress = _uniswapV2FactoryAddress;
        uniswapV3FactoryAddress = _uniswapV3FactoryAddress;
        nonfungiblePositionManagerAddress = _nonfungiblePositionManagerAddress;
        topTokens = new TokenData[](50);
    }

    function addTokenToCheck(address token) external {
        require(msg.sender == owner, "Only owner can add tokens");
        require(token != address(0), "Invalid token address");
        require(!isTokenInTop50[token], "Token already in top 50");
        isTokenInTop50[token] = true;
    }

    function getTop50PoolsByUsdcAmount(uint256 currentUSDC, address[] calldata tokensToAdd) external view returns (TokenData[] memory) {
    INonfungiblePositionManager positionManager = INonfungiblePositionManager(nonfungiblePositionManagerAddress);
    uint256 totalPositions = positionManager.totalSupply();

    TokenData[] memory result = new TokenData[](50);

    for (uint256 i = 1; i <= totalPositions; i++) {
        (, , address token0, address token1, , , , , , , ) = positionManager.positions(i);

        if (token0 == usdcTokenAddress || token1 == usdcTokenAddress) {
            (, int24 tickLower, int24 tickUpper, , , , , ) = positionManager.positions(i);

            uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick((tickLower + tickUpper) / 2);
            uint256 usdcAmount = (token0 == usdcTokenAddress) ? uint256(sqrtPriceX96) : uint256(uint192(sqrtPriceX96));
            uint256 adjustedUsdcAmount = usdcAmount * currentUSDC;

            address nonUsdcToken = (token0 == usdcTokenAddress) ? token1 : token0;

            if (!isTokenInTop50[nonUsdcToken]) {
                for (uint256 j = 0; j < 50; j++) {
                    if (adjustedUsdcAmount > topTokens[j].usdValue) {
                        for (uint256 k = 49; k > j; k--) {
                            topTokens[k] = topTokens[k - 1];
                        }
                        topTokens[j] = TokenData({token: nonUsdcToken, usdValue: adjustedUsdcAmount});
                        isTokenInTop50[nonUsdcToken] = true;
                        break;
                    }
                }
            }
        }
    }

    // copy top 50 tokens to result array
    for (uint256 i = 0; i < 50; i++) {
        result[i] = topTokens[i];
    }

    // check value of added tokens and add them to result if they are in the top 50
    for (uint256 i = 0; i < tokensToAdd.length; i++) {
        address token = tokensToAdd[i];
        if (!isTokenInTop50[token]) {
            uint256 usdValue = getUsdValue(token, currentUSDC);
            if (usdValue > topTokens[49].usdValue) {
                for (uint256 j = 49; j > 0; j--) {
                    if (usdValue > topTokens[j - 1].usdValue) {
                        topTokens[j] = topTokens[j - 1];
                    } else {
                        topTokens[j] = TokenData({token: token, usdValue: usdValue});
                        isTokenInTop50[token] = true;
                        break;
                    }
                }
            }
        }
    }

    // sort the final result array
    for (uint256 i = 0; i < result.length - 1; i++) {
        for (uint256 j = i + 1; j < result.length; j++) {
            if (result[j].usdValue > result[i].usdValue) {
                TokenData memory temp = result[i];
                result[i] = result[j];
                result[j] = temp;
           }
    }
}

// clear topTokens array for the next query
for (uint256 i = 0; i < 50; i++) {
    topTokens[i] = TokenData({token: address(0), usdValue: 0});
}

return result;
}

function getUsdValue(address token, uint256 currentUSDC) internal view returns (uint256) {
address[] memory path = new address;
path[0] = token;
path[1] = usdcTokenAddress;
uint256[] memory amounts = IUniswapV2Router02(uniswapV2FactoryAddress).getAmountsOut(currentUSDC, path);
return amounts[1];
}
