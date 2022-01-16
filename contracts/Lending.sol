// File: contracts/Lending.sol

pragma solidity ^0.8.4;

import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";

interface c_Interface {
    function transfer(address dst, uint amount) external returns (bool);
    function transferFrom(address src, address dst, uint amount) external returns (bool);
    function approve(address spender, uint amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint);
    function balanceOf(address owner) external view returns (uint);
    function balanceOfUnderlying(address owner) external returns (uint);
    function getAccountSnapshot(address account) external view returns (uint, uint, uint, uint);
    function borrowRatePerBlock() external view returns (uint);
    function supplyRatePerBlock() external view returns (uint);
    function totalBorrowsCurrent() external returns (uint);
    function borrowBalanceCurrent(address account) external returns (uint);
    function borrowBalanceStored(address account) external view returns (uint);
    function exchangeRateCurrent() external returns (uint);
    function exchangeRateStored() external view returns (uint);
    function getCash() external view returns (uint);
    function accrueInterest() external returns (uint);
    function seize(address liquidator, address borrower, uint seizeTokens) external returns (uint);
    function mint(uint mintAmount) external returns (uint);
    function redeem(uint redeemTokens) external returns (uint);
    function redeemUnderlying(uint redeemAmount) external returns (uint);
    function borrow(uint borrowAmount) external returns (uint);
    function repayBorrow(uint repayAmount) external returns (uint);
    function repayBorrowBehalf(address borrower, uint repayAmount) external returns (uint);
}

interface ERC20 {
    function balanceOf(address owner) external view returns (uint);
    function allowance(address owner, address spender) external view returns (uint);
    function approve(address spender, uint value) external returns (bool);
    function transfer(address to, uint value) external returns (bool);
    function transferFrom(address from, address to, uint value) external returns (bool); 
    function totalSupply() external view returns (uint256);
    function decimals() external view returns (uint8);
    function symbol() external view returns (string memory);
    function name() external view returns (string memory);
}

interface Comptroller_Interface {
      /*** Assets You Are In ***/

    function enterMarkets(address[] calldata cTokens) external returns (uint[] memory);
    function exitMarket(address cToken) external returns (uint);

    /*** Policy Hooks ***/

    function mintAllowed(address cToken, address minter, uint mintAmount) external returns (uint);
    function mintVerify(address cToken, address minter, uint mintAmount, uint mintTokens) external;

    function redeemAllowed(address cToken, address redeemer, uint redeemTokens) external returns (uint);
    function redeemVerify(address cToken, address redeemer, uint redeemAmount, uint redeemTokens) external;

    function borrowAllowed(address cToken, address borrower, uint borrowAmount) external returns (uint);
    function borrowVerify(address cToken, address borrower, uint borrowAmount) external;

    function repayBorrowAllowed(
        address cToken,
        address payer,
        address borrower,
        uint repayAmount) external returns (uint);
    function repayBorrowVerify(
        address cToken,
        address payer,
        address borrower,
        uint repayAmount,
        uint borrowerIndex) external;

    function liquidateBorrowAllowed(
        address cTokenBorrowed,
        address cTokenCollateral,
        address liquidator,
        address borrower,
        uint repayAmount) external returns (uint);
    function liquidateBorrowVerify(
        address cTokenBorrowed,
        address cTokenCollateral,
        address liquidator,
        address borrower,
        uint repayAmount,
        uint seizeTokens) external;

    function seizeAllowed(
        address cTokenCollateral,
        address cTokenBorrowed,
        address liquidator,
        address borrower,
        uint seizeTokens) external returns (uint);
    function seizeVerify(
        address cTokenCollateral,
        address cTokenBorrowed,
        address liquidator,
        address borrower,
        uint seizeTokens) external;

    function transferAllowed(address cToken, address src, address dst, uint transferTokens) external returns (uint);
    function transferVerify(address cToken, address src, address dst, uint transferTokens) external;

    /*** Liquidity/Liquidation Calculations ***/

    function liquidateCalculateSeizeTokens(
        address cTokenBorrowed,
        address cTokenCollateral,
        uint repayAmount) external view returns (uint, uint);


    function getAccountLiquidity(address account) external view returns (uint, uint, uint);
}

interface UniswapAnchoredView{
    function price(string memory symbol) external view returns (uint);
}

interface IWETH9 {
    function deposit() external payable;
    function withdraw(uint wad) external;
}

contract lendingprotocol{

    c_Interface internal cETH;
    c_Interface internal cDai;
    ERC20 internal Dai;
    Comptroller_Interface internal Comptroller;
    UniswapAnchoredView internal Uniswapanchor;

    uint256 internal count_transcation_borrow;
    address public Owner;
    uint24 internal constant poolFee = 3000;

    address private constant DAI_Address = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address private constant WETH9_Address = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant USDC_Address = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    mapping(address => uint) private _depositvalueETH;
    mapping(address => uint) private _valueofborrow_ETH;
    mapping(address => uint) private _valuecETHofuser;
    mapping(address => uint) private _valuecETHrequest;
    mapping(address => uint) public _valueofborrow_Dai;
    mapping(address => uint) public _wrapunwrapeth;
    
    ISwapRouter private swapRouter;

    event Deposit_Event(address from,uint256 ValueOfETH,uint256 ValueofcETH);
    event EnterMarkets_Event(address[] cTokens,uint[] error_code);
    event ExitBackETH_Event(address user,uint256 value);
    event UnderlyingPool_Event(c_Interface coin,uint value);

    // ceth = 0x4ddc2d193948926d02f9b1fe9e1daa0718270ed5
    // cdai = 0x5d3a536e4d6dbd6114cc1ead35777bab948e3643
    // dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F
    // comptroller = 0x3d9819210a31b4961b30ef54be2aed79b9c9cd3b comptroller is comptroller address that shoot to
    // uniswap = 0x046728da7cb8272284238bd3e47909823d63a58d (PriceFeed)
    // swaprouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564 
    // "0x4ddc2d193948926d02f9b1fe9e1daa0718270ed5","0x5d3a536e4d6dbd6114cc1ead35777bab948e3643","0x6B175474E89094C44Da98b954EedeAC495271d0F","0x3d9819210a31b4961b30ef54be2aed79b9c9cd3b","0x046728da7cb8272284238bd3e47909823d63a58d","0xE592427A0AEce92De3Edee1F18E0157C05861564" //
    constructor(address _ceth,address _cdai,address _dai,address _comptroller,address _uniswapanchor,address _swapRouter) {

        cETH = c_Interface(_ceth);
        cDai = c_Interface(_cdai);
        count_transcation_borrow = 0;
        Comptroller = Comptroller_Interface(_comptroller);
        Uniswapanchor = UniswapAnchoredView(_uniswapanchor);
        Owner = msg.sender;
        Dai = ERC20(_dai);
        swapRouter = ISwapRouter(_swapRouter);

    }

    // this function for mint //
    function Deposit() public payable {
        
        (,uint before_cbalance,,) =  cETH.getAccountSnapshot(address(this));
        (bool status,) = address(cETH).call{value: msg.value}("");
        require(status, "Lending: Failed to send Ether");
        (,uint after_cbalance,,) =  cETH.getAccountSnapshot(address(this));

        uint sum_ceth = after_cbalance - before_cbalance;

        _depositvalueETH[msg.sender] += msg.value; // เก็บว่าคนนี้ฝากมาเท่าไหร่ //
        _valuecETHofuser[msg.sender] += sum_ceth; // เก็บว่าคนนี้หลังจากฝากมา เขาได้ cETH กลับไปเท่าไหร่ //

    
        emit Deposit_Event(msg.sender,msg.value,sum_ceth);
        

          if(count_transcation_borrow == 0) {
            EnterMarkets(address(cETH));
          }
          
    }

    modifier OnlyOwner {
        require(msg.sender == Owner,"Lending: You are not owner.");
        _;
    }

    function WithdrawcDai(uint256 value) private {
        cDai.transfer(msg.sender,value);
    }

    // EnterMarket for approve that value widthdraw for can request borrow //
    function EnterMarkets(address ccoin) private {
        address[] memory data = new address[](1);
        data[0] = ccoin;

        (uint[] memory err_code) = Comptroller.enterMarkets(data); // ใส่ [address(cETH)] ตรงๆไม่ได้เนื่องจาก address[1] มันไม่เท่ากับ address[]


        emit EnterMarkets_Event(data,err_code);
    }
    
    // value เอามาจาก RealValuethatusercanborrow_DAI //
    // ซือ ETH จากการยืม DAI //
    function BuyETHfromDai(uint value) public  returns (uint256 amountOut) {
        require( _depositvalueETH[msg.sender] >0 ,"Lending: You not buy anything.");
        require(RealValuethatusercanborrow_DAI(msg.sender) >= value,"Lending: The amount cannot be more than the approved amount.");

        BorrowDai(msg.sender,value);

        // Approve the router to spend DAI.
        TransferHelper.safeApprove(DAI_Address, address(swapRouter), value);

        // Naively set amountOutMinimum to 0. In production, use an oracle or other data source to choose a safer value for amountOutMinimum.
        // We also set the sqrtPriceLimitx96 to be 0 to ensure we swap our exact input amount.
        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: DAI_Address,
                tokenOut: WETH9_Address,
                fee: poolFee,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: value,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        // The call to `exactInputSingle` executes the swap.
        amountOut = swapRouter.exactInputSingle(params);
        _wrapunwrapeth[msg.sender] += amountOut;
        ERC20(WETH9_Address).transfer(msg.sender,amountOut);
        return amountOut;
    }

    function DepositwETHtoDai(uint value) public payable returns (uint256 amountOut) { // ขาย wETH จากการยืม DAI //
        require(_wrapunwrapeth[msg.sender] >= value,"Lending: Insufficient.");
        require(_valueofborrow_Dai[msg.sender] > 0,"Lending: You aren't borrow.");
        require(ERC20(WETH9_Address).allowance(msg.sender,address(this)) >= value,"Lending: Insufficient Allowance.");
        require(ERC20(WETH9_Address).balanceOf(msg.sender) >= value,"Lending: Insufficient Balance.");
        ERC20(WETH9_Address).transferFrom(msg.sender,address(this),value);
        _wrapunwrapeth[msg.sender] -= amountOut;
        // Approve the router to spend WETH9.
        TransferHelper.safeApprove(WETH9_Address, address(swapRouter), value);

        // Naively set amountOutMinimum to 0. In production, use an oracle or other data source to choose a safer value for amountOutMinimum.
        // We also set the sqrtPriceLimitx96 to be 0 to ensure we swap our exact input amount.
        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: WETH9_Address,
                tokenOut: DAI_Address,
                fee: poolFee,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: value,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

         // The call to `exactInputSingle` executes the swap.
        amountOut = swapRouter.exactInputSingle(params);
        

        //(>0 -> 3000 - 2800) (< 0 || == 0 -> 2800 - 3000 )
    
        if(amountOut > _valueofborrow_Dai[msg.sender]) {
            Dai.approve(msg.sender,amountOut - _valueofborrow_Dai[msg.sender]);
            Dai.transfer(msg.sender,amountOut - _valueofborrow_Dai[msg.sender]); // ไม่รวมเคสในกรณีที่คิด เปอร์เซ้นต์ //
            
            (,,uint borrow_balance,) =  cDai.getAccountSnapshot(address(this));
    
            Dai.approve(address(cDai),borrow_balance);
            
            cDai.repayBorrow(_valueofborrow_Dai[msg.sender]); // pay 
            _valueofborrow_Dai[msg.sender] -= _valueofborrow_Dai[msg.sender];
 
            ExitBackETH(msg.sender,_depositvalueETH[msg.sender]); // redeem back from cETH to ETH //

        }else if(amountOut <= _valueofborrow_Dai[msg.sender]) {
            (,,uint borrow_balance,) =  cDai.getAccountSnapshot(address(this));
          
    
            Dai.approve(address(cDai),borrow_balance);
            cDai.repayBorrow(amountOut); // pay 
            _valueofborrow_Dai[msg.sender] -= amountOut;
 

            ExitBackETH(msg.sender, (amountOut*Price("DAI"))/Price("ETH")); // redeem back from cETH to ETH //
        }

        return amountOut;
    }

    function unwrap(uint256 amountOut) public {
        require(_wrapunwrapeth[msg.sender] >= amountOut,"Lending: Insufficient WETH9 of You.");
        IWETH9(WETH9_Address).withdraw(amountOut);
        (bool status,) = msg.sender.call{value: amountOut}("");
        require(status, "Lending: Failed to send Ether");

        _wrapunwrapeth[msg.sender] -= amountOut;
    }  

    function AccountSnapshot(c_Interface coin) public view returns(uint err_code,uint balance,uint borrow,uint exchangerate) {
        return coin.getAccountSnapshot(address(this));
    }

    function ExitBackETH(address _user,uint256 _value) private  {
        require(_depositvalueETH[_user] >= _value,"Lending: You are not deposit.");
        require(cETH.balanceOfUnderlying(address(this)) >= _value,"Lending: Underlying Error.");
        (,uint Liquidity,) = Comptroller.getAccountLiquidity(address(this));
        require(Liquidity >= _value,"Lending: AccountLiquidity Insufficient");
        (,uint ceth_before,,) = AccountSnapshot(cETH);

        require(cETH.redeemUnderlying(_value) == 0, "Lending: something went wrong"); // redeem  <-- ERROR //

        (,uint ceth_after,,) = AccountSnapshot(cETH);

        uint sum = ceth_before - ceth_after;

        (bool status,) = _user.call{value: _value}("");
        require(status, "Lending: Failed to send Ether");
        _valuecETHofuser[_user] -= sum;
        _depositvalueETH[_user] -= _value;

        emit ExitBackETH_Event(_user,_value);


    }


    // ทำกำไรจากการแปลง dai ที่ยืมไปขายเป็น eth แล้วเมื่อ eth ขึ้น ก็ทำกำไรจาก eth ที่ยืมมาไปขายคืนเป็น dai แล้วเอาไปคืน
    function BorrowDai(address user,uint value) private {

        require(RealValuethatusercanborrow_DAI(user) >= value,"Lending: The amount cannot be more than the approved amount.");
        if(count_transcation_borrow == 0) {
            EnterMarkets(address(cETH));
            cDai.borrow(value); // borrow // 
        }else {
            cDai.borrow(value); // borrow // 
        }

        // Dai.transfer(user,value); // ไม่ส่งเพราะเอาไปรวมเลยง่ายดี
        _valueofborrow_Dai[user] += value;
        count_transcation_borrow += 1;

    }

    function PayBackBorrowDai(address user,uint value) private {

        require(_valueofborrow_Dai[user] > 0,"Lending: You aren't borrow.");
         (,,uint borrow_balance,) =  cETH.getAccountSnapshot(address(this));
        Dai.transferFrom(msg.sender,address(this),value);
        Dai.approve(address(cDai),borrow_balance);

        cDai.repayBorrow(value); // pay 
        _valueofborrow_Dai[msg.sender] -= value;

    }

    // value deciamls 8 // // unused // 
    function WidthdrawcETH(uint value) private {
        require(_valuecETHofuser[msg.sender] >= value,"Lending: Balance Insufficient.");
        require(_valuecETHofuser[msg.sender] - _valuecETHrequest[msg.sender] >= value,"Lending: You not have more request value for widthdraw.");
        
        cETH.transfer(msg.sender,value);
        _valuecETHrequest[msg.sender] += value;
        
    }

    // value deciamls 8 // // unused // 
    function DepositcETH(uint value) private {
    
        require(_valuecETHrequest[msg.sender] >= value ,"Lending: You not have any reqeust.");
        require(cETH.allowance(msg.sender,address(this)) >= value,"Lending: You are not approve this contract.");
        require(cETH.balanceOf(msg.sender) >= value,"Lending: Balance Insufficient.");
        cETH.transferFrom(msg.sender,address(this),value);
        _valuecETHrequest[msg.sender] -= value;
    
    }

    function BalancethatUserdeposit(address user) public view returns(uint) {
        return _depositvalueETH[user];
    }

    function BalanceCoin(address user,address coin) public view returns(uint256) {
        return ERC20(coin).balanceOf(user);
    }

    function BalanceETHPool() public view returns(uint256) {
        return address(this).balance;
    }

    function Format_Balance(address user,address coin) public view returns(uint256) {
        return ERC20(coin).balanceOf(user) / 10**Dai.decimals();
    }

    function BalanceOfcETH(address user) public view returns(uint256) {
        return _valuecETHofuser[user];
    }

    // เอาราคา ETH หรือ DAI หรือ อื่นๆ (Oracle) //
    function Price(string memory symbol) public view returns(uint){
        return Uniswapanchor.price(symbol);
    }

    function Valuethatusercanborrow_DAI(address user) private view returns(uint) {
        return ((BalancethatUserdeposit(user) *  (Price("ETH")) / (Price("DAI")))*799) / 1000;
    }

    function RealValuethatusercanborrow_DAI(address user) public view returns(uint) {
        return (Valuethatusercanborrow_DAI(user)) -  _valueofborrow_Dai[user];
    }

}