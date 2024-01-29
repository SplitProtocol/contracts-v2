// SPDX-License-Identifier: MIT

// *************************************************************************************************************************************
// *************************************************************************************************************************************
// *****************.     .,*/**********************************************************************************************************
// ************                 ,*******************************************************************************************************
// *********.          .         **********************************************************************/********************************
// ********      ############ ,**********&@@@@@@@@@@@@@@@@/****@@@@@@@@@@@@@@@@@@%/**%@&*************/@@****&@@@@@@@@@@@@@@@@@@@&/******
// *******     #############*   ********@@***************/*****@@**************/*@@**%@&**************@@*************%@&****************
// *****/     #####**(###(**    .*******@@@********************@@****************%@@*%@&**************@@*************%@&****************
// ******     ####********/##     *********&@@@@@#/************@@***************/@@**%@&**************@@*************%@&****************
// ******.    ###***/****/####    *****************%@@@@@/*****@@@@@@@@@@@@@@@@@@****%@&**************@@*************%@&****************
// *******     /**####**(###%.    ***********************@@@***@@********************%@&**************@@*************%@&****************
// ********,  .(############,     ************************@@***@@*********************@@**************@@*************%@&****************
// ********** (###########..     *******@@@@@@@@@@@@@@@@@@@****@@**********************@@@@@@@@@%(****@@*************%@&****************
// *******,           .       .*************/((((((((/*********//*************************************/*********************************
// ********.                .***********************************************************************************************************
// *************.     .,****************************************************************************************************************
// *************************************************************************************************************************************
// *************************************************************************************************************************************

pragma solidity 0.8.13;

contract SplitRouterV2 {

    struct SwapData {
        uint256 volume;
        uint256 date;
        uint256 swapTxValue;
        address fromToken;
        address swapTxRouter;
        address trader;
        bytes32 partner;
        bytes swapTxInputData;
    }

    event OwnershipTransferred(address indexed owner);
    event MinProfitChanged(uint256 profitMin);

    address private deployer;
    uint256 public minProfit;
    uint256 public burntSPLX;
    mapping(address => bool) private isWorker;
    // mapping(uint256 => uint256) tradeVolumePerDay;
    // mapping(uint256 => uint256) totalMevCollectedPerDay;
    // mapping(uint256 => uint256) tradersMevCollectedPerDay;
    // mapping(uint256 => uint256) routerSwapsPerDay;
    // mapping(uint256 => mapping(uint256 => address)) routerSwapAddrsPerDay;
    // mapping(uint256 => uint256) mevTxsPerDay;
    // mapping(uint256 => mapping(uint256 => address)) mevAddrsPerDay;
    address private immutable WETH;
    address private constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    modifier onlyOwner() {
        require(msg.sender == deployer, "Split: Not allowed");
        _;
    }

    modifier onlyWorker() {
        require(isWorker[msg.sender], "Split: Not allowed");
        _;
    }

    constructor(address _weth, address[] memory _workers) {
        deployer = msg.sender;
        WETH = _weth;
        for (uint256 i = 0; i < _workers.length; i++) {
            isWorker[_workers[i]] = true;
        }
    }

    receive() external payable {

    }

    fallback() external payable {

    }

    function transferOwnership(address owner) external onlyOwner {
        deployer = owner;
        emit OwnershipTransferred(owner);
    }

    function destroySelf() external onlyOwner {
        assembly {
            selfdestruct(caller())
        }
    }

    function rescueFunds(address token) external onlyOwner {
        assembly {
            if eq(token, ETH) {
                if iszero(call(gas(), caller(), balance(address()), 0, 0, 0, 0)) { revert(0, 0) }
            }
            if iszero(eq(token, ETH)) {
                let ptr := mload(0x40)
                mstore(ptr, shl(0xe0, 0x70a08231))
                mstore(add(ptr, 0x04), address())
                if iszero(staticcall(gas(), token, ptr, 0x24, ptr, 0x20)) { revert(0, 0) }
                let amount := mload(ptr)
                mstore(ptr, shl(0xe0, 0xa9059cbb))
                mstore(add(ptr, 0x04), caller())
                mstore(add(ptr, 0x24), amount)
                if iszero(call(gas(), token, 0, ptr, 0x44, 0, 0)) { revert(0, 0) }
            }
        }
    }

    function setWorkerStatus(bool status, address[] calldata workers) external onlyOwner {
        for (uint256 i = 0; i < workers.length; i++) {
            isWorker[workers[i]] = status;
        }
    }

    function setMinProfit(uint256 profitMin) external onlyOwner {
        minProfit = profitMin;
        emit MinProfitChanged(profitMin);
    }

    function swap(uint256 txfee, address[] calldata usedTokens, bytes calldata swapData, bytes calldata jitData, bytes calldata arbData) external onlyWorker {
        SwapData memory data = abi.decode(swapData);
        require(data.volume > 0, "Split: volume is 0");
        require(data.fromToken != ETH, "Split: fromToken is native");
        {
            uint256 volume = data.volume;
            address fromToken = data.fromToken;
            address trader = data.trader;
            address swaprouter = data.swapTxRouter;
            assembly {
                let ptr := mload(0x40)
                mstore(ptr, shl(0xe0, 0x23b872dd))
                mstore(add(ptr, 0x04), trader)
                mstore(add(ptr, 0x24), address())
                mstore(add(ptr, 0x44), volume)
                if iszero(call(gas(), fromToken, 0, ptr, 0x64, 0, 0)) { revert(0, 0) }
                mstore(ptr, shl(0xe0, 0x095ea7b3))
                mstore(add(ptr, 0x04), swaprouter)
                mstore(add(ptr, 0x24), volume)
                if iszero(call(gas(), fromToken, 0, ptr, 0x44, 0, 0)) { revert(0, 0) }
            }
        }
        uint256[] memory usedTokensBeforeBalances = new uint256[](usedTokens.length);
        for (uint256 i = 0; i < usedTokens.length; i++) {
            usedTokensBeforeBalances[i] = _balanceOf(address(this), usedTokens[i]);
        }
        (bool outSuccess, bytes memory outData) = data.swapTxRouter.call{value: data.swapTxValue}(data.swapTxInputData);
        if (!outSuccess) {
            if (outData.length == 0) {
                revert("Split: swap failed");
            } else {
                assembly {
                    revert(add(outData, 32), mload(outData))
                }
            }
        }
        for (uint256 i = 0; i < usedTokens.length; i++) {
            uint256 usedTokenBalance = _balanceOf(address(this), usedTokens[i]);
            if (usedTokenBalance > usedTokensBeforeBalances[i]) {
                uint256 deltaAmount = usedTokenBalance - usedTokensBeforeBalances[i];
                address usedToken = usedTokens[i];
                address trader = data.trader;
                assembly {
                    let ptr := mload(0x40)
                    
                }
            }
        }
    }

    function _balanceOf(address account, address token) internal view returns (uint256 bal) {
        assembly {
            if eq(token, ETH) {
                bal := balance(account)
            }
            if iszero(eq(token, ETH)) {
                let ptr := mload(0x40)
                mstore(ptr, shl(0xe0, 0x70a08231))
                mstore(add(ptr, 0x04), account)
                if iszero(staticcall(gas(), token, ptr, 0x24, ptr, 0x20)) { revert(0, 0) }
                bal := mload(ptr)
            }
        }
    }
}