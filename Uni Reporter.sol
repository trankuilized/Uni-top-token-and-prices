pragma solidity ^0.8.0;

import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Top50Pools {
    address public owner;
    address public usdcTokenAddress;

    mapping(address => bool) public isTokenInTop50;
    mapping(address => bool) public managers;
    mapping(address => bool) public positionManagers;
    mapping(address => bool) public uniswapFactories;

    struct TokenDataWithPoolSize {
        address token;
        uint256 usdValue;
        uint256 poolSize;
        uint256 tokenPrice;
        address factory;
        address positionManager;
        address reserveToken;
    }

    TokenDataWithPoolSize[] private topTokens;

    constructor(address _usdcTokenAddress) {
        owner = msg.sender;
        usdcTokenAddress = _usdcTokenAddress;

        topTokens = new TokenDataWithPoolSize[](50);
        for (uint256 i = 0; i < 50; i++) {
            topTokens[i] = TokenDataWithPoolSize({
                token: address(0),
                usdValue: 0,
                poolSize: 0,
                tokenPrice: 0,
                factory: address(0),
                positionManager: address(0),
                reserveToken: address(0)
            });
        }
    }

    function getTop50PoolsByUsdcAmount(
        uint256 currentUSDC,
        address[] calldata tokensToAdd,
        address[] calldata _uniswapFactories,
        address[] calldata _positionManagers
    ) external view returns (TokenDataWithPoolSize[] memory) {
        TokenDataWithPoolSize[] memory result = new TokenDataWithPoolSize[](50);

        for (uint256 f = 0; f < _uniswapFactories.length; f++) {
            for (uint256 p = 0; p < _positionManagers.length; p++) {
                if (
                    uniswapFactories[_uniswapFactories[f]] &&
                    positionManagers[_positionManagers[p]]
                ) {
                    INonfungiblePositionManager positionManager = INonfungiblePositionManager(
                            _positionManagers[p]
                        );
                    uint256 totalPositions = positionManager.totalSupply();

                    for (uint256 i = 1; i <= totalPositions; i++) {
                        (
                            ,
                            ,
                            address token0,
                            address token1,
                            uint24 fee,
                            int24 tickLower,
                            int24 tickUpper,
                            uint128 liquidity,
                            ,
                            ,

                        ) = positionManager.positions(i);

                        if (
                            token0 == usdcTokenAddress ||
                            token1 == usdcTokenAddress
                        ) {
                            (
                                ,
                                ,
                                ,
                                ,
                                ,
                                ,
                                ,
                                ,
                                ,
                                uint256 amount0,
                                uint256 amount1
                            ) = positionManager.positions(i);

                            address reserveToken;
                            uint256 reserveAmount;
                            if (token0 == usdcTokenAddress) {
                                reserveToken = token1;
                                reserveAmount = amount1;
                            } else {
                                reserveToken = token0;
                                reserveAmount = amount0;
                            }

                            uint256 usdcAmount = (token0 == usdcTokenAddress)
                                ? amount0
                                : amount1;
                            uint256 adjustedUsdcAmount = usdcAmount *
                                currentUSDC;

                            TokenDataWithPoolSize
                                memory tokenData = TokenDataWithPoolSize({
                                    token: reserveToken,
                                    usdValue: adjustedUsdcAmount,
                                    poolSize: reserveAmount,
                                    tokenPrice: getUsdValue(
                                        reserveToken,
                                        currentUSDC
                                    ),
                                    factory: _uniswapFactories[f],
                                    positionManager: _positionManagers[p],
                                    reserveToken: reserveToken
                                });
                            bool isTokenInResult = false;
                            for (uint256 j = 0; j < result.length; j++) {
                                if (result[j].token == tokenData.token) {
                                    result[j].usdValue += tokenData.usdValue;
                                    result[j].poolSize += tokenData.poolSize;
                                    isTokenInResult = true;
                                    break;
                                }
                            }

                            if (!isTokenInResult) {
                                for (uint256 j = 0; j < result.length; j++) {
                                    if (
                                        tokenData.usdValue > result[j].usdValue
                                    ) {
                                        for (
                                            uint256 k = result.length - 1;
                                            k > j;
                                            k--
                                        ) {
                                            result[k] = result[k - 1];
                                        }
                                        result[j] = tokenData;
                                        isTokenInTop50[tokenData.token] = true;
                                        break;
                                    }
                                }
                            }

                            for (uint256 j = 0; j < 50; j++) {
                                if (
                                    adjustedUsdcAmount > topTokens[j].usdValue
                                ) {
                                    for (uint256 k = 49; k > j; k--) {
                                        topTokens[k] = topTokens[k - 1];
                                    }
                                    topTokens[j] = TokenDataWithPoolSize({
                                        token: reserveToken,
                                        usdValue: adjustedUsdcAmount,
                                        poolSize: reserveAmount,
                                        tokenPrice: getUsdValue(
                                            reserveToken,
                                            currentUSDC
                                        ),
                                        factory: _uniswapFactories[f],
                                        positionManager: _positionManagers[p],
                                        reserveToken: reserveToken
                                    });
                                    break;
                                }
                            }
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
                            topTokens[j] = TokenDataWithPoolSize({
                                token: token,
                                usdValue: usdValue,
                                poolSize: getPoolSize(token, currentUSDC),
                                tokenPrice: getUsdValue(token, currentUSDC),
                                factory: address(0),
                                positionManager: address(0),
                                reserveToken: address(0)
                            });
                            isTokenInTop50[token] = true;
                            break;
                        }
                    }
                }
            }
        }

        // check value of all tokens, including those that are not in the top 50
        for (uint256 f = 0; f < _uniswapFactories.length; f++) {
            for (uint256 p = 0; p < _positionManagers.length; p++) {
                if (
                    uniswapFactories[_uniswapFactories[f]] &&
                    positionManagers[_positionManagers[p]]
                ) {
                    INonfungiblePositionManager positionManager = INonfungiblePositionManager(
                            _positionManagers[p]
                        );
                    uint256 totalPositions = positionManager.totalSupply();
                    for (uint256 i = 1; i <= totalPositions; i++) {
                        (
                            ,
                            ,
                            address token0,
                            address token1,
                            uint24 fee,
                            int24 tickLower,
                            int24 tickUpper,
                            uint128 liquidity,
                            ,
                            ,

                        ) = positionManager.positions(i);

                        if (
                            token0 != usdcTokenAddress &&
                            token1 != usdcTokenAddress
                        ) {
                            (
                                uint256 token0Reserve,
                                uint256 token1Reserve,

                            ) = IUniswapV2Pair(address(uint160(token0)))
                                    .getReserves();
                            (uint256 reserve0, uint256 reserve1) = token0 ==
                                address(positionManager)
                                ? (token0Reserve, token1Reserve)
                                : (token1Reserve, token0Reserve);

                            uint256 totalSupply = IERC20(
                                address(positionManager)
                            ).totalSupply();
                            uint256 lpAmount = (liquidity * totalSupply) /
                                positionManager.balanceOf(
                                    address(positionManager),
                                    tickLower,
                                    tickUpper
                                );

                            uint256 token0Amount = (token0 ==
                                address(positionManager))
                                ? ((lpAmount * reserve0) / liquidity)
                                : ((lpAmount * reserve1) / liquidity);
                            uint256 token1Amount = (token0 ==
                                address(positionManager))
                                ? ((lpAmount * reserve1) / liquidity)
                                : ((lpAmount * reserve0) / liquidity);

                            address reserveToken = (token0 ==
                                address(positionManager))
                                ? token1
                                : token0;
                            uint256 reserveAmount = (token0 ==
                                address(positionManager))
                                ? token1Amount
                                : token0Amount;

                            uint256 usdcAmount = getUsdValue(
                                reserveToken,
                                currentUSDC
                            ) * reserveAmount;
                            TokenDataWithPoolSize
                                memory tokenData = TokenDataWithPoolSize({
                                    token: reserveToken,
                                    usdValue: usdcAmount,
                                    poolSize: lpAmount,
                                    tokenPrice: getUsdValue(
                                        reserveToken,
                                        currentUSDC
                                    ),
                                    factory: _uniswapFactories[f],
                                    positionManager: _positionManagers[p],
                                    reserveToken: reserveToken
                                });

                            bool isTokenInResult = false;
                            for (uint256 j = 0; j < result.length; j++) {
                                if (result[j].token == tokenData.token) {
                                    result[j].usdValue += tokenData.usdValue;
                                    result[j].poolSize += tokenData.poolSize;
                                    isTokenInResult = true;
                                    break;
                                }
                            }

                            if (!isTokenInResult) {
                                for (uint256 j = 0; j < result.length; j++) {
                                    if (
                                        tokenData.usdValue > result[j].usdValue
                                    ) {
                                        for (
                                            uint256 k = result.length - 1;
                                            k > j;
                                            k--
                                        ) {
                                            result[k] = result[k - 1];
                                        }
                                        result[j] = tokenData;
                                        break;
                                    }
                                }
                            }

                            if (
                                !isTokenInTop50[tokenData.token] &&
                                tokenData.usdValue > topTokens[49].usdValue
                            ) {
                                for (uint256 j = 49; j > 0; j--) {
                                    if (
                                        tokenData.usdValue >
                                        topTokens[j - 1].usdValue
                                    ) {
                                        topTokens[j] = topTokens[j - 1];
                                    } else {
                                        topTokens[j] = tokenData;
                                        isTokenInTop50[tokenData.token] = true;
                                        break;
                                    }
                                }
                            }
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
                uint256 poolSize = getPoolSize(token, currentUSDC);
                address factory = address(0);
                address positionManager = address(0);
                address reserveToken = address(0);
                for (uint256 f = 0; f < _uniswapFactories.length; f++) {
                    if (uniswapFactories[_uniswapFactories[f]]) {
                        address pair = IUniswapV2Factory(_uniswapFactories[f])
                            .getPair(token, usdcTokenAddress);
                        if (pair != address(0)) {
                            factory = _uniswapFactories[f];
                            positionManager = address(positionManagers[pair]);
                            reserveToken = (token == pair)
                                ? usdcTokenAddress
                                : token;
                            break;
                        }
                    }
                }
                TokenDataWithPoolSize memory tokenData = TokenDataWithPoolSize({
                    token: token,
                    usdValue: usdValue,
                    poolSize: poolSize,
                    tokenPrice: getUsdValue(token, currentUSDC),
                    factory: factory,
                    positionManager: positionManager,
                    reserveToken: reserveToken
                });
                if (usdValue > topTokens[49].usdValue) {
                    for (uint256 j = 49; j > 0; j--) {
                        if (usdValue > topTokens[j - 1].usdValue) {
                            topTokens[j] = topTokens[j - 1];
                        } else {
                            topTokens[j] = tokenData;
                            isTokenInTop50[tokenData.token] = true;
                            break;
                        }
                    }
                }
            }
        }

        // check value of all tokens, including those that are not in the top 50
        for (uint256 i = 0; i < tokensToCheck.length; i++) {
            address token = tokensToCheck[i];
            if (!isTokenInTop50[token]) {
                uint256 usdValue = getUsdValue(token, currentUSDC);
                uint256 poolSize = getPoolSize(token, currentUSDC);
                address factory = address(0);
                address positionManager = address(0);
                address reserveToken = address(0);
                for (uint256 f = 0; f < _uniswapFactories.length; f++) {
                    if (uniswapFactories[_uniswapFactories[f]]) {
                        address pair = IUniswapV2Factory(_uniswapFactories[f])
                            .getPair(token, usdcTokenAddress);
                        if (pair != address(0)) {
                            factory = _uniswapFactories[f];
                            positionManager = address(positionManagers[pair]);
                            reserveToken = (token == pair)
                                ? usdcTokenAddress
                                : token;
                            break;
                        }
                    }
                }
                TokenDataWithPoolSize memory tokenData = TokenDataWithPoolSize({
                    token: token,
                    usdValue: usdValue,
                    Size: poolSize,
                    tokenPrice: getUsdValue(token, currentUSDC),
                    factory: factory,
                    positionManager: positionManager,
                    reserveToken: reserveToken
                });
                bool isTokenInResult = false;
                for (uint256 j = 0; j < result.length; j++) {
                    if (result[j].token == tokenData.token) {
                        result[j].usdValue += tokenData.usdValue;
                        result[j].poolSize += tokenData.poolSize;
                        isTokenInResult = true;
                        break;
                    }
                }
                if (!isTokenInResult) {
                    for (uint256 j = 0; j < result.length; j++) {
                        if (tokenData.usdValue > result[j].usdValue) {
                            for (uint256 k = result.length - 1; k > j; k--) {
                                result[k] = result[k - 1];
                            }
                            result[j] = tokenData;
                            break;
                        }
                    }
                }
            }
        }
        return result;
    }

    /**
     * @notice Adds a new Uniswap V2 or V3 factory to be used for finding liquidity pools
     * @param factory The address of the factory to add
     */
    function addUniswapFactory(address factory) external onlyOwner {
        require(factory != address(0), "Invalid factory address");
        uniswapFactories[factory] = true;
    }

    /**
     * @notice Removes a Uniswap V2 or V3 factory from being used for finding liquidity pools
     * @param factory The address of the factory to remove
     */
    function removeUniswapFactory(address factory) external onlyOwner {
        delete uniswapFactories[factory];
    }

    /**
     * @notice Adds a new Uniswap V3 position manager to be used for finding liquidity pools
     * @param positionManager The address of the position manager to add
     */
    function addPositionManager(address positionManager) external onlyOwner {
        require(
            positionManager != address(0),
            "Invalid position manager address"
        );
        positionManagers[positionManager] = true;
    }

    /**
     * @notice Removes a Uniswap V3 position manager from being used for finding liquidity pools
     * @param positionManager The address of the position manager to remove
     */
    function removePositionManager(address positionManager) external onlyOwner {
        delete positionManagers[positionManager];
    }

    /**
     * @notice Adds tokens to be checked for liquidity, even if they are not in the top 50
     * @param tokens The addresses of the tokens to add
     */
    function addTokensToCheck(
        address[] memory tokens
    ) external onlyOwnerOrManager {
        for (uint256 i = 0; i < tokens.length; i++) {
            if (!isTokenInTop50[tokens[i]]) {
                tokensToCheck.push(tokens[i]);
            }
        }
    }

    /**
     * @notice Removes tokens from being checked for liquidity, even if they are in the top 50
     * @param tokens The addresses of the tokens to remove
     */
    function removeTokensToCheck(
        address[] memory tokens
    ) external onlyOwnerOrManager {
        for (uint256 i = 0; i < tokens.length; i++) {
            for (uint256 j = 0; j < tokensToCheck.length; j++) {
                if (tokensToCheck[j] == tokens[i]) {
                    delete tokensToCheck[j];
                    break;
                }
            }
        }
    }

    /**
     * @notice Adds tokens to be checked for liquidity, and if they are in the top 50
     * they will be included in the output array
     * @param tokens The addresses of the tokens to add
     */
    function addTokensToTop50(
        address[] memory tokens
    ) external onlyOwnerOrManager {
        for (uint256 i = 0; i < tokens.length; i++) {
            if (!isTokenInTop50[tokens[i]]) {
                tokensToAdd.push(tokens[i]);
            }
        }
    }

    /**
     * @notice Removes tokens from being checked for liquidity, and removes them from the output array if they are in the top 50
     * @param tokens The addresses of the tokens to remove
     */
    function removeTokensFromTop50(
        address[] memory tokens
    ) external onlyOwnerOrManager {
        for (uint256 i = 0; i < tokens.length; i++) {
            for (uint256 j = 0; j < tokensToAdd.length; j++) {
                if (tokensToAdd[j] == tokens[i]) {
                    delete tokensToAdd[j];
                    break;
                }
            }
            if (isTokenInTop50[tokens[i]]) {
                for (uint256 j = 0; j < 50; j++) {
                    if (topTokens[j].token == tokens[i]) {
                        for (uint256 k = j; k < 49; k++) {
                            topTokens[k] = topTokens[k + 1];
                        }
                        topTokens[49] = TokenDataWithPoolSize({
                            token: address(0),
                            usdValue: 0,
                            poolSize: 0,
                            tokenPrice: 0,
                            factory: address(0),
                            positionManager: address(0),
                            reserveToken: address(0)
                        });
                        isTokenInTop50[tokens[i]] = false;
                        break;
                    }
                }
            }
        }
    }
}
