// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "../Unitls//ReentrancyGuard.sol";
import "../Comment/TransferHelper.sol";
import "../Comment/IUniswapV2Factory.sol";
import "../Comment/IPresaleLockForwarder.sol";
import "../Comment/IWETH.sol";
import "../Comment/IPresaleSettings.sol";
import "../Comment/IERC20Custom.sol";

contract Presale01 is ReentrancyGuard {
    struct PresaleInfo {
        address payable PRESALE_OWNER;
        IERC20Custom S_TOKEN; // sale token
        IERC20Custom B_TOKEN; // base token // usually WETH (ETH)
        uint256 TOKEN_PRICE; // 1 base token = ? s_tokens, fixed price
        uint256 MAX_SPEND_PER_BUYER; // maximum base token BUY amount per account
        uint256 MIN_SPEND_PER_BUYER; // maximum base token BUY amount per account
        uint256 AMOUNT; // the amount of presale tokens up for presale
        uint256 HARDCAP;
        uint256 SOFTCAP;
        uint256 LIQUIDITY_PERCENT; // divided by 1000
        uint256 LISTING_RATE; // fixed rate at which the token will list on uniswap
        uint256 START_TIME;
        uint256 END_TIME;
        uint256 LOCK_PERIOD; // unix timestamp -> e.g. 2 weeks
        uint256 UNISWAP_LISTING_TIME;
        bool PRESALE_IN_ETH; // if this flag is true the presale is raising ETH, otherwise an ERC20 token such as DAI
        uint8 ADD_LP;
    }

    struct PresaleFeeInfo {
        uint256 DAOLAUNCH_BASE_FEE; // divided by 1000
        uint256 DAOLAUNCH_TOKEN_FEE; // divided by 1000
        address payable BASE_FEE_ADDRESS;
        address payable TOKEN_FEE_ADDRESS;
    }

    struct PresaleStatus {
        bool WHITELIST_ONLY; // if set to true only whitelisted members may participate
        bool LIST_ON_UNISWAP;
        bool IS_TRANSFERED_FEE;
        bool IS_OWNER_WITHDRAWN;
        uint256 TOTAL_BASE_COLLECTED; // total base currency raised (usually ETH)
        uint256 TOTAL_TOKENS_SOLD; // total presale tokens sold
        uint256 TOTAL_TOKENS_WITHDRAWN; // total tokens withdrawn post successful presale
        uint256 TOTAL_BASE_WITHDRAWN; // total base tokens withdrawn on presale failure
        uint256 NUM_BUYERS; // number of unique participants
    }

    struct BuyerInfo {
        uint256 baseDeposited; // total base token (usually ETH) deposited by user, can be withdrawn on presale failure
        uint256 tokensOwed; // num presale tokens a user is owed, can be withdrawn on presale success
        uint256 lastWithdraw; // day of the last withdrawing. If first time => = firstDistributionType
        uint256 totalTokenWithdraw; // number of tokens withdraw
        bool isWithdrawnBase;
    }

    struct GasLimit {
        uint256 transferPresaleOwner;
        uint256 listOnUniswap;
    }

    struct VestingPeriod {
        // if set time for user withdraw at listing : use same data in uint_params[11], otherwise set new Date for it
        uint256 firstDistributionType;
        uint256 firstUnlockRate;
        uint256 distributionInterval;
        uint256 unlockRateEachTime;
        uint256 maxPeriod;
    }

    //Strust
    PresaleInfo private PRESALE_INFO;
    PresaleFeeInfo public PRESALE_FEE_INFO;
    PresaleStatus public STATUS;
    address public PRESALE_GENERATOR;
    IPresaleLockForwarder public PRESALE_LOCK_FORWARDER;
    IPresaleSettings public PRESALE_SETTINGS;
    IUniswapV2Factory public UNI_FACTORY;
    IWETH public WETH;
    mapping(address => BuyerInfo) public BUYERS;
    address payable public CALLER;
    GasLimit public GAS_LIMIT;
    address payable public DAOLAUNCH_DEV;
    VestingPeriod public VESTING_PERIOD;
    mapping(address => bool) public admins;

    constructor(address _presaleGenerator, address[] memory _admins) payable {
        PRESALE_GENERATOR = _presaleGenerator;
        UNI_FACTORY = IUniswapV2Factory(
            0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73
        );
        WETH = IWETH(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
        PRESALE_SETTINGS = IPresaleSettings(
            0xcFb2Cb97028c4e2fe6b868D685C00ab96e6Ec370
        );
        PRESALE_LOCK_FORWARDER = IPresaleLockForwarder(
            0x57f443f5A891fC53C43b6D9Fb850fC068af76bF4
        );
        GAS_LIMIT = GasLimit(200000, 4000000);
        DAOLAUNCH_DEV = payable(0x75d69272c5A9d6FCeC0D68c547776C7195f73feA);
        for (uint256 i = 0; i < _admins.length; i++) {
            admins[_admins[i]] = true;
        }
    }

    function init1(address payable _presaleOwner, uint256[11] memory data)
        external
    {
        require(msg.sender == PRESALE_GENERATOR, "FORBIDDEN");
        PRESALE_INFO.PRESALE_OWNER = _presaleOwner;
        PRESALE_INFO.AMOUNT = data[0];
        PRESALE_INFO.TOKEN_PRICE = data[1];
        PRESALE_INFO.MAX_SPEND_PER_BUYER = data[2];
        PRESALE_INFO.MIN_SPEND_PER_BUYER = data[3];
        PRESALE_INFO.HARDCAP = data[4];
        PRESALE_INFO.SOFTCAP = data[5];
        PRESALE_INFO.LIQUIDITY_PERCENT = data[6];
        PRESALE_INFO.LISTING_RATE = data[7];
        PRESALE_INFO.START_TIME = data[8];
        PRESALE_INFO.END_TIME = data[9];
        PRESALE_INFO.LOCK_PERIOD = data[10];
    }

    function init2(
        IERC20Custom _baseToken,
        IERC20Custom _presaleToken,
        uint256[3] memory data,
        address payable _baseFeeAddress,
        address payable _tokenFeeAddress
    ) external {
        require(msg.sender == PRESALE_GENERATOR, "FORBIDDEN");

        PRESALE_INFO.PRESALE_IN_ETH = address(_baseToken) == address(WETH);
        PRESALE_INFO.S_TOKEN = _presaleToken;
        PRESALE_INFO.B_TOKEN = _baseToken;
        PRESALE_FEE_INFO.DAOLAUNCH_BASE_FEE = data[0];
        PRESALE_FEE_INFO.DAOLAUNCH_TOKEN_FEE = data[1];
        PRESALE_INFO.UNISWAP_LISTING_TIME = data[2];

        PRESALE_FEE_INFO.BASE_FEE_ADDRESS = _baseFeeAddress;
        PRESALE_FEE_INFO.TOKEN_FEE_ADDRESS = _tokenFeeAddress;
    }

    function init3(
        bool is_white_list,
        address payable _caller,
        uint256[5] memory data,
        uint8 _addLP
    ) external {
        require(msg.sender == PRESALE_GENERATOR, "FORBIDDEN");
        STATUS.WHITELIST_ONLY = is_white_list;
        CALLER = _caller;
        // Change spec of token Vesting - Update contract presale
        VESTING_PERIOD.firstDistributionType = data[0];
        VESTING_PERIOD.firstUnlockRate = data[1];
        VESTING_PERIOD.distributionInterval = data[2];
        VESTING_PERIOD.unlockRateEachTime = data[3];
        VESTING_PERIOD.maxPeriod = data[4];

        PRESALE_INFO.ADD_LP = _addLP;
    }

    modifier onlyPresaleOwner() {
        require(PRESALE_INFO.PRESALE_OWNER == msg.sender, "NOT PRESALE OWNER");
        _;
    }

    modifier onlyAdmin() {
        require(admins[msg.sender], "NOT ADMIN");
        _;
    }

    modifier onlyPresaleOwnerOrAdmin() {
        require(PRESALE_INFO.PRESALE_OWNER == msg.sender || admins[msg.sender], "NOT PRESALE OWNER OR ADMIN");
        _;
    }

    modifier onlyCaller() {
        require(CALLER == msg.sender, "NOT PRESALE CALLER");
        _;
    }

    modifier onlyValidAccess(
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) {
        if (STATUS.WHITELIST_ONLY) {
            require(
                isValidAccessMsg(msg.sender, _v, _r, _s),
                "NOT WHITELISTED"
            );
        }
        _;
    }

    function isValidAccessMsg(
        address _addr,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) internal view returns (bool) {
        bytes32 hash = keccak256(abi.encodePacked(address(this), _addr));

        return
            DAOLAUNCH_DEV ==
            ecrecover(
                keccak256(
                    abi.encodePacked("\x19Ethereum Signed Message:\n32", hash)
                ),
                _v,
                _r,
                _s
            );
    }

    function presaleStatus() public view returns (uint256) {
        if (
            (block.timestamp > PRESALE_INFO.END_TIME) &&
            (STATUS.TOTAL_BASE_COLLECTED < PRESALE_INFO.SOFTCAP)
        ) {
            return 3; // FAILED - softcap not met by end block
        }
        if (STATUS.TOTAL_BASE_COLLECTED >= PRESALE_INFO.HARDCAP) {
            return 2; // SUCCESS - hardcap met
        }
        if (
            (block.timestamp > PRESALE_INFO.END_TIME) &&
            (STATUS.TOTAL_BASE_COLLECTED >= PRESALE_INFO.SOFTCAP)
        ) {
            return 2; // SUCCESS - endblock and soft cap reached
        }
        if (
            (block.timestamp >= PRESALE_INFO.START_TIME) &&
            (block.timestamp <= PRESALE_INFO.END_TIME)
        ) {
            return 1; // ACTIVE - deposits enabled
        }
        return 0; // QUED - awaiting start block
    }

    // accepts msg.value for eth or _amount for ERC20 tokens

    function userDeposit(
        uint256 _amount,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external payable onlyValidAccess(_v, _r, _s) nonReentrant {
        require(presaleStatus() == 1, "NOT ACTIVE"); // ACTIVE

        BuyerInfo storage buyer = BUYERS[msg.sender];
        uint256 amount_in = PRESALE_INFO.PRESALE_IN_ETH ? msg.value : _amount;
        // Check amount_in great then value of MIN_SPEND_PER_BUYER
        require(
            amount_in >= PRESALE_INFO.MIN_SPEND_PER_BUYER,
            "NOT ENOUGH VALUE"
        );
        uint256 allowance = PRESALE_INFO.MAX_SPEND_PER_BUYER -
            buyer.baseDeposited;
        uint256 remaining = PRESALE_INFO.HARDCAP - STATUS.TOTAL_BASE_COLLECTED;
        allowance = allowance > remaining ? remaining : allowance;
        if (amount_in > allowance) {
            amount_in = allowance;
        }
        uint256 tokensSold = (amount_in * PRESALE_INFO.TOKEN_PRICE) /
            (10**uint256(PRESALE_INFO.B_TOKEN.decimals()));
        require(tokensSold > 0, "ZERO TOKENS");
        if (buyer.baseDeposited == 0) {
        // Imcrement buyer onr unit when baseDepositOfBuyter == 0    
            STATUS.NUM_BUYERS++;
        }
        buyer.baseDeposited += amount_in;
        buyer.tokensOwed += tokensSold;
        STATUS.TOTAL_BASE_COLLECTED += amount_in;
        STATUS.TOTAL_TOKENS_SOLD += tokensSold;
        // return unused ETH 
        if (PRESALE_INFO.PRESALE_IN_ETH && amount_in < msg.value) {
        // User transfer amount token for presale    
            payable(msg.sender).transfer(msg.value - amount_in);
        }
        // deduct non ETH token from user
        // If not fee of presale is not ETH
        if (!PRESALE_INFO.PRESALE_IN_ETH) {
            TransferHelper.safeTransferFrom(
                address(PRESALE_INFO.B_TOKEN),
                msg.sender,
                address(this),
                amount_in
            );
        }
    }

    // withdraw presale tokens
    // percentile withdrawls allows fee on transfer or rebasing tokens to still work
    // User with draw token when presale success
    function userWithdrawTokens() external nonReentrant {  
        // User with draw token success  
        // Check presaleStatus of presale equal 2 => Status success
        require(presaleStatus() == 2, "NOT SUCCESS"); // SUCCESS
        // Check block.timeStamp of block great then firstDistributionType
        // Check time great then
        require(
            block.timestamp >= VESTING_PERIOD.firstDistributionType,
            "NOT NOW"
        );
    // Check number token sale great then number token withdraw    
    // Check TOTAL_TOKENS_SOLD - TOTAL_TOKEN_WITHDRAW > 0
        require(
            STATUS.TOTAL_TOKENS_SOLD - STATUS.TOTAL_TOKENS_WITHDRAW > 0,
            "ALL TOKEN HAS BEEN WITHDRAWN"
        );
    // Check transtion of chain mode
    // Check status ADD_LP != 2 => different Off_Chain -> On_Chain or distribution
        require(PRESALE_INFO.ADD_LP != 2, "OFF-CHAIN MODE");
    // Get information of buyer through BUYERS[msg.sender]    
        BuyerInfo storage buyer = BUYERS[msg.sender];
    // Set rateWithdrowAfter    
        uint256 rateWithdrawAfter;
    // Save currentTime    
        uint256 currentTime;
    // Check block.timeswap great then max periiod
        if (block.timestamp > VESTING_PERIOD.maxPeriod) {
    // This right => set currentTime equal maxPeriod (time)                
            currentTime = VESTING_PERIOD.maxPeriod;
        } else {
    // This wrong => currentTime < VESTING_PERIOD.maxPeriod        
            currentTime = block.timestamp;
        }    
    // Get owner token of buyer = buyer.tokensOwned
        uint256 tokensOwed = buyer.tokensOwed;
    // If VESTING_PERIOP.firstUnlockRate equal 100 => Fully
        if (VESTING_PERIOD.firstUnlockRate == 100) {
    // Check total token with draw different tokenOwned    
    // else => Already withdraw all  
            require(
                buyer.totalTokenWithdraw != tokensOwed,
                "Already withdraw all"
            );
    // Set rate with draw after eq
            rateWithdrawAfter = 100;
        } else {
    // Calculate spentCycles between Current time and first distribution, all / distributionInterval
            uint256 spentCycles = (currentTime -
                VESTING_PERIOD.firstDistributionType) /
                VESTING_PERIOD.distributionInterval; // (m' - m0)/k
            // Not yet withdrow token 
            if (buyer.lastWithdraw == 0) {
            // Get data time     
                rateWithdrawAfter =
                    spentCycles *
                    VESTING_PERIOD.unlockRateEachTime +
                    VESTING_PERIOD.firstUnlockRate; //x + spentCycles*y
            } else {
            // Get current time when buyer withdraw some time     
                uint256 lastSpentCycles = (buyer.lastWithdraw -
                    VESTING_PERIOD.firstDistributionType) /
                    VESTING_PERIOD.distributionInterval; // (LD - M0)/k
                rateWithdrawAfter = 
                    (spentCycles - lastSpentCycles) *
                    VESTING_PERIOD.unlockRateEachTime; //(spentCycles - lastSpentCycles)*y
                require(rateWithdrawAfter > 0, "INVALID MOMENT"); // SUCCESS
            }
        }
        // Set buyer -> lastTimeDraw equal current time
        buyer.lastWithdraw = currentTime;
        // Calculate amount buyer can with draw 
        uint256 amountWithdraw = (tokensOwed * rateWithdrawAfter) / 100;

        if (buyer.totalTokenWithdraw + amountWithdraw > buyer.tokensOwed) {
            amountWithdraw = buyer.tokensOwed - buyer.totalTokenWithdraw;
        }

        STATUS.TOTAL_TOKENS_WITHDRAWN += amountWithdraw;
        buyer.totalTokenWithdraw += amountWithdraw; // update total token withdraw of buyer address
        // Backtoken ETH for user
        TransferHelper.safeTransfer(
            address(PRESALE_INFO.S_TOKEN), // Token ERC20
            msg.sender,
            amountWithdraw
        );
    }

    // on presale failure
    // percentile withdrawls allows fee on transfer or rebasing tokens to still work
    // User with draw base token (ERC20 OF presale) 
    
    function userWithdrawBaseTokens() external nonReentrant {
        // Check status equal 3
        require(presaleStatus() == 3, "NOT FAILED"); // FAILED
        // GET information of user BUYERS[msg.sender]
        BuyerInfo storage buyer = BUYERS[msg.sender];
        // Check status of isWithdrawnBase = false => Not yet withDraw
        require(!buyer.isWithdrawnBase, "NOTHING TO REFUND");
        // Set status of TOTAL_BASE_WITHDRAWN
        STATUS.TOTAL_BASE_WITHDRAWN += buyer.baseDeposited;
        // 
        TransferHelper.safeTransferBaseToken(
            address(PRESALE_INFO.B_TOKEN), // From: ETH when user presale token
            payable(msg.sender),           // Payable
            buyer.baseDeposited,           // Number token baseDeposited
            !PRESALE_INFO.PRESALE_IN_ETH   // Status of presale_in_eth = false -> Not must be token ETH 
        );
        buyer.isWithdrawnBase = true;
    }

    // on presale failure
    // allows the owner to withdraw the tokens they sent for presale & initial liquidity
    // Admin create presale token failure 
    function ownerRefundTokens() external onlyPresaleOwner {
    // Status success     
        require(presaleStatus() == 3, "NOT FAILED"); // FAILED
    // Check is_owner_withdraw
        require(!STATUS.IS_OWNER_WITHDRAWN, "NOTHING TO WITHDRAW");
    // transfer token ERC20 for owner of presale
        TransferHelper.safeTransfer(
            address(PRESALE_INFO.S_TOKEN), // Back token ERC20 for owner
            PRESALE_INFO.PRESALE_OWNER,
            PRESALE_INFO.S_TOKEN.balanceOf(address(this))
        );
    // Set with draw equal true    
        STATUS.IS_OWNER_WITHDRAWN = true;
    // Send eth fee to owner, send presale for owner
        PRESALE_INFO.PRESALE_OWNER.transfer(  // transfer fee create foe user create token
            PRESALE_SETTINGS.getEthCreationFee() 
        );
    //     
    }

    // on presale success, this is the final step to end the presale, lock liquidity and enable withdrawls of the sale token.
    // This function does not use percentile distribution. Rebasing mechanisms, fee on transfers, or any deflationary logic
    // are not taken into account at this stage to ensure stated liquidity is locked and the pool is initialised according to
    // the presale parameters and fixed prices.
    // Sale presale success => With draw all data in presale

    function listOnUniswap() external onlyCaller {
        // Check time great then listtinf time
        require(
            block.timestamp >= PRESALE_INFO.UNISWAP_LISTING_TIME,
            "Call listOnUniswap too early"
        );
        // Check sta7tus need equal 2 => Status success
        require(presaleStatus() == 2, "NOT SUCCESS"); // SUCCESS
        // Check not yet transaction_fee
        require(!STATUS.IS_TRANSFERED_FEE, "TRANSFERED FEE");
        // Require(PRESALE_INFO.LIQUIDITY_PERCENT > 0, "LIQUIDITY_PERCENT = 0");
        // ADD_LP = 2 is off chian mode
        if (PRESALE_INFO.ADD_LP == 2) {
            // off-chain mode
            // send all to DAOLaunch, remaining listing fee to presale owner
            // send all base token
            TransferHelper.safeTransferBaseToken(
            //  Transfer TOTAL_BASE_COLLECTED from B_TOKEN to BASE_FEE_ADDRESS
                address(PRESALE_INFO.B_TOKEN),
                PRESALE_FEE_INFO.BASE_FEE_ADDRESS,
                STATUS.TOTAL_BASE_COLLECTED,
                !PRESALE_INFO.PRESALE_IN_ETH
            );
            
            // send all token
            // Get number token of: balanceOf (address(this) = address of smart contract)
            uint256 tokenBalance = PRESALE_INFO.S_TOKEN.balanceOf(address(this));
            // Transfer tokenBalance from S_TOKEN to TOKEN_FEE_ADDRESS (TOKEN_FEE_COLLECTED)
            TransferHelper.safeTransfer(
                address(PRESALE_INFO.S_TOKEN),
                PRESALE_FEE_INFO.TOKEN_FEE_ADDRESS,
                tokenBalance
            );
            // send transaction fee
            // Calculate txFee
            uint256 txFee = tx.gasprice * GAS_LIMIT.transferPresaleOwner;
            // txFee less then PRESALE_SETTINGS
            require(txFee <= PRESALE_SETTINGS.getEthCreationFee());
            // Transfer fee to CALLER
            CALLER.transfer(txFee);
            // 
            PRESALE_INFO.PRESALE_OWNER.transfer(
                PRESALE_SETTINGS.getEthCreationFee() - txFee
            );
            return;
        }
        // Get BaseFee of token Token Fee 
        uint256 DAOLaunchBaseFee = (STATUS.TOTAL_BASE_COLLECTED *
            PRESALE_FEE_INFO.DAOLAUNCH_BASE_FEE) / 1000;
        // base token liquidity 
        uint256 baseLiquidity = ((STATUS.TOTAL_BASE_COLLECTED -
            DAOLaunchBaseFee) * PRESALE_INFO.LIQUIDITY_PERCENT) / 1000;
        // Deposit baseLiquidity to address WETH
        if (PRESALE_INFO.ADD_LP == 0 && baseLiquidity > 0 && PRESALE_INFO.PRESALE_IN_ETH) {
            WETH.deposit{value: baseLiquidity}();
        }
        // Transfer baseLiquidity from B_TOKEN to PRESALE_LOCK_FORWARDER
        if (PRESALE_INFO.ADD_LP == 0 && baseLiquidity > 0) {
            TransferHelper.safeApprove(
                address(PRESALE_INFO.B_TOKEN),
                address(PRESALE_LOCK_FORWARDER),
                baseLiquidity
            );
        }

        // Sale token liquidity
        // Get number tokenLiquidity
        uint256 tokenLiquidity = (baseLiquidity * PRESALE_INFO.LISTING_RATE) /
            (10**uint256(PRESALE_INFO.B_TOKEN.decimals()));

        // transfer fees
        // Get DAOLaunchTokenFee 
        uint256 DAOLaunchTokenFee = (STATUS.TOTAL_TOKENS_SOLD *
            PRESALE_FEE_INFO.DAOLAUNCH_TOKEN_FEE) / 1000;
        // Check DAOLaunchTokenFee great then 0    
        if (DAOLaunchBaseFee > 0) {
        // Transfer DAOLaunchTokenFee from B_TOKEN to BASE_FEE_ADDRESS 
            TransferHelper.safeTransferBaseToken(
                address(PRESALE_INFO.B_TOKEN), 
                PRESALE_FEE_INFO.BASE_FEE_ADDRESS,
                DAOLaunchBaseFee,
                !PRESALE_INFO.BASE_FEE_ADDRESS
            );
        }
        // Check DAOLaunchTokenFee great then 0
        if (DAOLaunchTokenFee > 0) {
        // Transfer to TOKEN_FEE_ADDRESS
            TransferHelper.safeTransfer(
                address(PRESALE_INFO.S_TOKEN),
                PRESALE_FEE_INFO.TOKEN_FEE_ADDRESS,
                DAOLaunchTokenFee
            );
        }
        // Set IS_TRANSFERED_FEE is true
        STATUS.IS_TRANSFERED_FEE = true;

        // if use escrow or percent = 0%
        // Mode onChain 
        // Check ADD_LD = 1
        if (PRESALE_INFO.ADD_LP == 1 || baseLiquidity == 0) {
            // transfer fee to DAOLaunch 
            uint256 txFee = tx.gasprice * GAS_LIMIT.transferPresaleOwner;
            require(txFee <= PRESALE_SETTINGS.getEthCreationFee());           
            if (baseLiquidity == 0) {
                // send fee to project owner
                // Transfer fee transaction from address(this) to PRESALE_OWNER
                PRESALE_INFO.PRESALE_OWNER.transfer(
                    PRESALE_SETTINGS.getEthCreationFee() - txFee
                );
            } else {
                // send fee to DAOLaunch
                // Transfer fee from address(this) to BASE_FEE_ADDRESS
                PRESALE_FEE_INFO.BASE_FEE_ADDRESS.transfer(
                    PRESALE_SETTINGS.getEthCreationFee() - txFee
                );
            }
            
            // send transaction fee
            CALLER.transfer(txFee);
        } else {
            // transfer fee to DAOLaunch
            uint256 txFee = tx.gasprice * GAS_LIMIT.listOnUniswap;
            require(txFee <= PRESALE_SETTINGS.getEthCreationFee());

            // send fee to DAOLaunch
            // transfer Fee to address(this) to BASE_FEE_ADDRESS
            PRESALE_FEE_INFO.BASE_FEE_ADDRESS.transfer(
                PRESALE_SETTINGS.getEthCreationFee() - txFee
            );

            // send transaction fee
            CALLER.transfer(txFee);
        }

        if (PRESALE_INFO.ADD_LP == 1) {
            // Send liquidity to DAOLaunch
            // Transfer baseLiquidity from address of B_TOKEN to BASE_FEE_ADDRESS  
            TransferHelper.safeTransferBaseToken(
                address(PRESALE_INFO.B_TOKEN),
                PRESALE_FEE_INFO.BASE_FEE_ADDRESS,
                baseLiquidity,
                !PRESALE_INFO.PRESALE_IN_ETH
            );
            // Transfer tokenLiquidity from S_TOKEN to BASE_FEE_ADDRESS
            TransferHelper.safeTransfer(
                address(PRESALE_INFO.S_TOKEN),
                PRESALE_FEE_INFO.BASE_FEE_ADDRESS,
                tokenLiquidity
            );
        } else {
            if (baseLiquidity > 0) {
                // Fail the presale if the pair exists and contains presale token liquidity
                // Get pair of token Token ERC20
                if (
                    PRESALE_LOCK_FORWARDER.uniswapPairIsInitialised(
                        address(PRESALE_INFO.S_TOKEN),
                        address(PRESALE_INFO.B_TOKEN)
                    )
                ) {
                // Set uniwswap equal true    
                    STATUS.LIST_ON_UNISWAP = true;
                // Tranfer baseLiquidity from address of smart contract B_TOKEN to PRESALE_OWNER
                    TransferHelper.safeTransferBaseToken(
                        address(PRESALE_INFO.B_TOKEN),
                        PRESALE_INFO.PRESALE_OWNER,
                        baseLiquidity,
                        !PRESALE_INFO.PRESALE_IN_ETH
                    );
                // Transfer baseLiquidity from address of smart contract S_TOKEN to PRESALE_OWNER    
                    TransferHelper.safeTransfer(
                        address(PRESALE_INFO.S_TOKEN),
                        PRESALE_INFO.PRESALE_OWNER,
                        tokenLiquidity
                    );
                    return;
                }

                TransferHelper.safeApprove(
                    address(PRESALE_INFO.S_TOKEN),
                    address(PRESALE_LOCK_FORWARDER),
                    tokenLiquidity
                );

                PRESALE_LOCK_FORWARDER.lockLiquidity(
                    PRESALE_INFO.B_TOKEN,
                    PRESALE_INFO.S_TOKEN,
                    baseLiquidity,
                    tokenLiquidity,
                    block.timestamp + PRESALE_INFO.LOCK_PERIOD,
                    PRESALE_INFO.PRESALE_OWNER
                );
            }
        }
        STATUS.LIST_ON_UNISWAP = true;
    }

    function ownerWithdrawTokens() external nonReentrant onlyPresaleOwner {
    // Check status IS_OWNER_WITHDRAWN   
        require(!STATUS.IS_OWNER_WITHDRAWN, "GENERATION COMPLETE");
    // Check presale must equal 2   
        require(presaleStatus() == 2, "NOT SUCCESS"); // SUCCESS
    // Check ADD_LP different offchain
        require(PRESALE_INFO.ADD_LP != 2, "OFF-CHAIN MODE");
        uint256 DAOLaunchBaseFee = (STATUS.TOTAL_BASE_COLLECTED *
            PRESALE_FEE_INFO.DAOLAUNCH_BASE_FEE) / 1000;
        uint256 baseLiquidity = ((STATUS.TOTAL_BASE_COLLECTED -
            DAOLaunchBaseFee) * PRESALE_INFO.LIQUIDITY_PERCENT) / 1000;
        uint256 DAOLaunchTokenFee = (STATUS.TOTAL_TOKENS_SOLD *
            PRESALE_FEE_INFO.DAOLAUNCH_TOKEN_FEE) / 1000;
        uint256 tokenLiquidity = (baseLiquidity * PRESALE_INFO.LISTING_RATE) /
            (10**uint256(PRESALE_INFO.B_TOKEN.decimals()));

        // send remain unsold tokens to presale owner
        uint256 remainingSBalance = PRESALE_INFO.S_TOKEN.balanceOf(
            address(this)
        ) +
            STATUS.TOTAL_TOKENS_WITHDRAWN -
            STATUS.TOTAL_TOKENS_SOLD;

        // send remaining base tokens to presale owner
        uint256 remainingBaseBalance = PRESALE_INFO.PRESALE_IN_ETH
            ? address(this).balance
            : PRESALE_INFO.B_TOKEN.balanceOf(address(this));
        if (!STATUS.IS_TRANSFERED_FEE) {
            remainingBaseBalance -= DAOLaunchBaseFee;
            remainingSBalance -= DAOLaunchTokenFee;
        }
        if (!STATUS.LIST_ON_UNISWAP) {
            if (PRESALE_INFO.PRESALE_IN_ETH) {
                remainingBaseBalance -=
                    baseLiquidity +
                    PRESALE_SETTINGS.getEthCreationFee();
            } else {
                remainingBaseBalance -= baseLiquidity;
            }
            remainingSBalance -= tokenLiquidity;
        }

        if (remainingSBalance > 0) {
            TransferHelper.safeTransfer(
                address(PRESALE_INFO.S_TOKEN),
                PRESALE_INFO.PRESALE_OWNER,
                remainingSBalance
            );
        }

        TransferHelper.safeTransferBaseToken(
            address(PRESALE_INFO.B_TOKEN),
            PRESALE_INFO.PRESALE_OWNER,
            remainingBaseBalance,
            !PRESALE_INFO.PRESALE_IN_ETH
        );
        STATUS.IS_OWNER_WITHDRAWN = true;
    }
    // Update gas limit fot block
    function updateGasLimit(
        uint256 _transferPresaleOwner,
        uint256 _listOnUniswap
    ) external {
    // Check address for msg.sender must equal DAOLAUNCH_DEV
        require(msg.sender == DAOLAUNCH_DEV, "INVALID CALLER");
    // Transfer fee presale owner for new fee
        GAS_LIMIT.transferPresaleOwner = _transferPresaleOwner;
    // Transfer fee swap token on uniswap  
        GAS_LIMIT.listOnUniswap = _listOnUniswap;
    }
    // Update max token for sender (User buy token)
    function updateMaxSpendLimit(uint256 _maxSpend) external onlyPresaleOwnerOrAdmin {
        PRESALE_INFO.MAX_SPEND_PER_BUYER = _maxSpend;
    }

    // postpone or bring a presale forward, this will only work when a presale is inactive.
    // i.e. current start block > block.timestamp
    // Update start time and end time for presale
    function updateBlocks(uint256 _startTime, uint256 _endTime)
        external
        onlyPresaleOwnerOrAdmin
    {
    // Check start time great then time of blocktime    
        require(PRESALE_INFO.START_TIME > block.timestamp);
    // Check endTimt and startTime suitable for current time         
        require(_endTime - _startTime > 0);
    // Set new time for START TIME
        PRESALE_INFO.START_TIME = _startTime;
    // Set new time for END_TIME    
        PRESALE_INFO.END_TIME = _endTime;
    }

    // editable at any stage of the presale
    // Check white list suitable for user 
    function setWhitelistFlag(bool _flag) external onlyPresaleOwnerOrAdmin {
        STATUS.WHITELIST_ONLY = _flag;
    }
    
    // Update admin for presale and check flag for admin can change new address 
    function updateAdmin(address _adminAddr, bool _flag) external onlyAdmin {
        require(_adminAddr != address(0), "INVALID ADDRESS");
        admins[_adminAddr] = _flag;
    }

    // if uniswap listing fails, call this function to release eth
    function finalize() external {
    // Check address of msg.sender must equal address of DAOLAUNCH_DEV     
        require(msg.sender == DAOLAUNCH_DEV, "INVALID CALLER");
    // Get raming balance
        uint256 remainingBBalance;
    // Check presale to pay ETH or orther token     
        if (!PRESALE_INFO.PRESALE_IN_ETH) {
    // Other token        
            remainingBBalance = PRESALE_INFO.B_TOKEN.balanceOf(
                address(this)
            );
        } else {
    // Eth token        
            remainingBBalance = address(this).balance;
        }
    // Transfer token for (base token) in presale for owner address Base_token 
    // require presale_in_eth equal false
        TransferHelper.safeTransferBaseToken(
            address(PRESALE_INFO.B_TOKEN),
            PRESALE_FEE_INFO.BASE_FEE_ADDRESS,
            remainingBBalance,
            !PRESALE_INFO.PRESALE_IN_ETH
        );
    // Get address(this) in smart contract balance of token ERC20 
        uint256 remainingSBalance = PRESALE_INFO.S_TOKEN.balanceOf(
            address(this)
        );
    // Back token for owner for base fee address
        TransferHelper.safeTransfer(
            address(PRESALE_INFO.S_TOKEN),
            PRESALE_FEE_INFO.BASE_FEE_ADDRESS,
            remainingSBalance
        );
        selfdestruct(PRESALE_FEE_INFO.BASE_FEE_ADDRESS);
    }

    // editable at any stage of the presale
    function changePresaleType(bool _flag, uint256 _maxSpend) external onlyAdmin {
        STATUS.WHITELIST_ONLY = _flag;
        PRESALE_INFO.MAX_SPEND_PER_BUYER = _maxSpend;
    }
}
