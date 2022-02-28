
pragma solidity >=0.6.0 <0.8.0;

import '../proxy/OwnedUpgradeabilityProxy.sol';
import '../ownable/MultiOwnable.sol';
import '../../config/InternalSmartContractConfig.sol';
import '../basic/Address.sol';
import '../../wallet/UserWallet.sol';

contract UserWalletProxy is MultiOwnable{
  using Address for address payable;
  event DepositETH(address indexed sender, uint256 indexed amount);
  event GasFeeTransferred(address indexed gasFeeWallet, uint256 indexed gasUsed, uint256 indexed gasFeeCollected);    
  event TopUpPaymentWalletFailed(address indexed destPaymentWallet, uint256 indexed gasUsed, uint256 indexed accountBalance,  bytes revertReason);

  event TransferRequestFailed(address indexed dest, uint256 indexed userGasUsed, uint256 indexed amount, string assetName, bytes revertReason);
  event SubmitWithdrawFailed(address indexed dest, uint256 indexed userGasUsed, uint256 indexed amount, uint256 amountWithFee, string assetName, bytes revertReason);


  bytes32 private constant userWalletImplPosition = keccak256("net.eurus.implementation");
  uint256 private constant extraGasFee = 49000;


  bytes32 private constant internalSCPosition = keccak256("network.eurus.internalSC");

  function getInternalSCAddress() public view returns (address impl) {
    bytes32 position = internalSCPosition;
    assembly {
      impl := sload(position)
    }
  }

    /**
   * @dev Tells the address of the current implementation
   * @return impl address of the current implementation
   */
  function getUserWalletImplementation() public view returns (address impl) {
    bytes32 position = userWalletImplPosition;
    assembly {
      impl := sload(position)
    }
  }


  /**
   * @dev Sets the address of the current implementation
   * @param newAddr address representing the new implementation to be set
   */
  function setInternalSCAddress(address newAddr) public onlyOwner{
    bytes32 position = internalSCPosition;
    assembly {
      sstore(position, newAddr)
    }
  }

  /**
   * @dev For backward competible
   * @param newImplementation address representing the new implementation to be set
   */
  function setUserWalletImplementation(address newImplementation) public onlyOwner{
    bytes32 position = userWalletImplPosition;
     assembly {
      sstore(position, newImplementation)
     }
  }


  function topUpPaymentWallet(address paymentWalletAddr, uint256 /*amount*/, bytes memory /*signature*/) public {
    
    uint256 gasBegin = gasleft();

    address internalSCAddr = getInternalSCAddress();
    require(internalSCAddr != address(0), "InternalSCAddress is 0");

    InternalSmartContractConfig internalSC = InternalSmartContractConfig(internalSCAddr);
    address _impl = internalSC.getUserWalletAddress();
    require(_impl != address(0), "UserWalletAddress is 0");
    bytes memory ptr;
    uint256 offset;
    uint256 size;
    uint256 result;
    assembly {
      ptr := mload(0x40)
      calldatacopy(ptr, 0, calldatasize())
      result := delegatecall(gas(), _impl, ptr, calldatasize(), 0, 0)
      size := returndatasize()
      returndatacopy(ptr, 0, size)
      
      switch result
        case 0 {
          if gt (size, 0) {
              offset := add(ptr, 0x120)
              mstore(0x40, offset)
              ptr := add(ptr, 4)
              let lengthFieldLength := mload(ptr)
              ptr := add(ptr, lengthFieldLength)
            }
        }
    }

    address payable gasFeeWallet = payable(internalSC.getGasFeeWalletAddress());
    uint256 gasUsed = gasBegin - gasleft()  + internalSC.getCentralizedGasFeeAdjustment();
    gasFeeWallet.sendValue(gasUsed * tx.gasprice);
    uint256 currBalance = payable(this).balance;
    
    if (result == 0 ){
      emit TopUpPaymentWalletFailed(paymentWalletAddr, gasUsed, currBalance, ptr);
    } else {
      emit GasFeeTransferred(gasFeeWallet, gasUsed,  gasUsed * tx.gasprice);
       assembly{
         return (ptr, size) 
      }
    }
  }

  fallback () external payable  {
    address internalSCAddr = getInternalSCAddress();
    require(internalSCAddr != address(0), "InternalSCAddress is 0");

    InternalSmartContractConfig internalSC = InternalSmartContractConfig(internalSCAddr);
    address _impl = internalSC.getUserWalletAddress();
    require(_impl != address(0), "UserWalletAddress is 0");

    assembly {
      let ptr := mload(0x40)
      calldatacopy(ptr, 0, calldatasize())
      let result := delegatecall(gas(), _impl, ptr, calldatasize(), 0, 0)
      let size := returndatasize()
      returndatacopy(ptr, 0, size)

      switch result
      case 0 { revert(ptr, size) }
      default { return(ptr, size) }
    }
  }

  receive() external payable {
    if(msg.value>0){
      emit DepositETH(msg.sender,msg.value);
    }
  }

  function requestTransfer(address dest, string memory assetName, uint256 amount) public{
    address internalSCAddr = getInternalSCAddress();
    require(internalSCAddr != address(0), "InternalSCAddress is 0");

    InternalSmartContractConfig internalSC = InternalSmartContractConfig(internalSCAddr);
    address payable userWalletImpl = payable(internalSC.getUserWalletAddress());
    require(userWalletImpl != address(0), "UserWalletAddress is 0");

    (bool isSuccess, bytes memory data) = userWalletImpl.delegatecall(abi.encodeWithSignature("requestTransfer(address,string,uint256)",dest, assetName, amount));
    require(isSuccess, string(data));
  }

  //For backward competible
  function requestTransfer(address dest, string memory assetName, uint256 amount, bytes memory /*signature*/) public{
      uint256 gasBegin = gasleft();
      address _impl = getUserWalletImplementation();
      require(_impl != address(0), "getUserWalletImplementation is 0");

      bytes memory ptr; 
      uint256 offset; 
      assembly {
          ptr := mload(0x40)
          calldatacopy(ptr, 0, calldatasize())
          let result := delegatecall(gas(), _impl, ptr, calldatasize(), 0, 0)
          let size := returndatasize()
          returndatacopy(ptr, 0, size)
          
          switch result
          case 0{
              
              if gt (size, 0) {

                offset := add ( ptr, 0x120)
                mstore(0x40, offset)
                ptr := add(ptr, 4)
                let lengthFieldLength := mload(ptr)
                ptr := add(ptr, lengthFieldLength)
              }
          }
          default{
            return(ptr, size)
          }
      }

      (bool isSuccess, bytes memory data) = _impl.delegatecall(abi.encodeWithSignature("getGasFeeWalletAddress()"));
      if (!isSuccess){
        revert('Unable to call getGetFeeWalletAddress');
      }

      address gasFeeAddress = bytesToAddress(data);
      address payable gasFeeWallet = payable(gasFeeAddress);
      uint256 gasUsed = gasBegin - gasleft()  + extraGasFee;
      gasFeeWallet.transfer(gasUsed * tx.gasprice);
      emit TransferRequestFailed(dest, gasUsed, amount, assetName, ptr);
      emit GasFeeTransferred(gasFeeWallet, gasUsed * tx.gasprice,  gasUsed * tx.gasprice); //Event needs to forward competible, previous event only having wallet address and gas fee collected 2 args    
  }

  function submitWithdraw(address dest, uint256 withdrawAmount, uint256 amountWithFee, string memory assetName) public {
    address internalSCAddr = getInternalSCAddress();
    require(internalSCAddr != address(0), "InternalSCAddress is 0");

    InternalSmartContractConfig internalSC = InternalSmartContractConfig(internalSCAddr);
    address payable userWalletImpl = payable(internalSC.getUserWalletAddress());
    require(userWalletImpl != address(0), "UserWalletAddress is 0");

    (bool isSuccess, bytes memory data) = userWalletImpl.delegatecall(abi.encodeWithSignature("submitWithdraw(address,uint256,uint256,string)",dest, withdrawAmount, amountWithFee, assetName));
    require(isSuccess, string(data));
  }

  //For backward competible
  function submitWithdraw(address dest, uint256 withdrawAmount, uint256 amountWithFee, string memory assetName, bytes memory /*signature*/) public{
      uint256 gasBegin = gasleft();
      address _impl = getUserWalletImplementation();
      require(_impl != address(0), "getUserWalletImplementation is 0");

      bytes memory ptr; 
      uint256 offset; 
      assembly {
        ptr := mload(0x40)
        calldatacopy(ptr, 0, calldatasize())
        let result := delegatecall(gas(), _impl, ptr, calldatasize(), 0, 0)
        let size := returndatasize()
        returndatacopy(ptr, 0, size)
        
        switch result
        case 0{
            if gt (size, 0) {

               offset := add(ptr, 0x120)
               mstore(0x40, offset)
               ptr := add(ptr, 4)
               let lengthFieldLength := mload(ptr)
               ptr := add(ptr, lengthFieldLength)
             }
         }
        default{
          return(ptr, size)
        }
      }

 
      (bool isSuccess, bytes memory data) = _impl.delegatecall(abi.encodeWithSignature("getGasFeeWalletAddress()"));
      if (!isSuccess){
        revert('Unable to call getGetFeeWalletAddress');

       }

      address gasFeeAddress = bytesToAddress(data);
      address payable gasFeeWallet = payable(gasFeeAddress);
      uint256 gasUsed = gasBegin - gasleft()  + extraGasFee;
      gasFeeWallet.transfer(gasUsed * tx.gasprice);

      emit SubmitWithdrawFailed(dest, gasUsed, withdrawAmount, amountWithFee, assetName, ptr);
      emit GasFeeTransferred(gasFeeWallet, gasUsed * tx.gasprice,  gasUsed * tx.gasprice); //Event needs to forward competible, previous event only having wallet address and gas fee collected 2 args    
  }

  function  bytesToAddress(bytes memory b) private pure returns (address addr){
      assembly {
        addr := mload(add(b, 32))
      }
  }

}
