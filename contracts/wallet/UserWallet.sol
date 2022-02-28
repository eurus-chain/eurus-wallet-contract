pragma solidity >=0.6.0 <0.8.0;
pragma experimental ABIEncoderV2;

import "./MultiSigWallet.sol";
import "../config/InternalSmartContractConfig.sol";
import "../erc20/basic/ERC20.sol";
import "../erc20/extend/EurusERC20.sol";
import "../utils/basic/Address.sol";
import "../erc20/extend/SafeERC20.sol";

contract UserWallet is MultiSigWallet{

    using Address for address payable;
    using SafeERC20 for ERC20;

    uint[] public TranList;
    InternalSmartContractConfig internalSmartContractContract;

    event TransferRequestEvent(uint256 indexed transactionId,  address indexed dest, string assetName,  uint256 amount);
    event WithdrawRequestEvent(address indexed dest, uint256 indexed withdrawAmount,  string assetName, uint256 amountWithFee);
    event TransferEvent(uint256 indexed transactionId,  address indexed dest, string assetName, uint256 indexed amount);
    event TopUpPaymentWalletEvent(address indexed dest, uint256 indexed targetGasWei, uint256 indexed gasTransferred);

    string constant internal assetNameKeyName = "assetName";
    string constant internal destAddressKeyName = "destAddress";
    


    constructor() MultiSigWallet(2) public {
    }

    function setInternalSmartContractConfig(address addr) public 
    onlyOwner{
        internalSmartContractContract = InternalSmartContractConfig(addr);
    }

    function requestTransferV1(address dest, string memory assetName, uint256 amount) public isWalletOwner(_msgSender()){
    
        address tmp ;
        bool isEun = false;
        if (keccak256(abi.encodePacked("EUN")) == keccak256(abi.encodePacked(assetName))){
            isEun = true;
        }

        if (!isEun) {
            tmp = internalSmartContractContract.getErc20SmartContractAddrByAssetName(assetName);
        }

        uint transId;

        if(tmp!=address(0) || isEun ){
            transId = addTransaction(dest, amount, "");
            transactions[transId].isDirectInvokeData = false;  
            miscellaneousData[transId][assetNameKeyName] = assetName;
            miscellaneousData[transId][destAddressKeyName] = string(abi.encode(dest));
            
            confirmations[transId][walletOwner] = true;
            Confirmation(walletOwner, transId);
            if (required == 1){
                executeTransaction(transId);
            }
            TranList.push(transId);

        }else{
            revert("Invalid asset!");
        }

        emit TransferRequestEvent(transId, dest, assetName, amount);
    }

    function getGasFeeWalletAddress() public view returns(address){
        return internalSmartContractContract.getGasFeeWalletAddress();
    }

    function verifySignature(bytes32 hash, bytes memory signature) public pure returns (address) {
        address addressFromSig = recoverSigner(hash, signature);
        return addressFromSig;
    }
//
//    /**
//    * @dev Recover signer address from a message by using their signature
//    * @param hash bytes32 message, the hash is the signed message. What is recovered is the signer address.
//    * @param sig bytes signature, the signature is generated using web3.eth.sign(). Inclusive "0x..."
//    */
    function recoverSigner(bytes32 hash, bytes memory sig) private pure returns (address) {
        require(sig.length == 65, "Require correct length");

        bytes32 r;
        bytes32 s;
        uint8 v;

        // Divide the signature in r, s and v variables
        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }

        // Version of signature should be 27 or 28, but 0 and 1 are also possible versions
        if (v < 27) {
            v += 27;
        }

        require(v == 27 || v == 28, "Signature version not match");

        return recoverSigner2(hash, v, r, s);
    }

    function recoverSigner2(bytes32 h, uint8 v, bytes32 r, bytes32 s) internal pure returns (address) {
        address addr = ecrecover(h, v, r, s);
        return addr;
    }


    function transfer(uint256 transId, address dest,string memory assetName, uint256 amount) internal{

        if (keccak256(abi.encodePacked("EUN")) == keccak256(abi.encodePacked(assetName))){
            payable(dest).sendValue(amount);
        }else{
            address erc20Addr = internalSmartContractContract.getErc20SmartContractAddrByAssetName(assetName);
            if(erc20Addr!=address(0)){
                ERC20 erc20 = ERC20(erc20Addr);
                erc20.safeTransfer(dest, amount);
            }else{
                revert("Invalid asset!");
            }
        }

        emit TransferEvent(transId, dest, assetName, amount);
    }

    function executeTransaction(uint transId) override internal
    confirmed(transId, msg.sender)
    {
        Transaction storage txn = transactions[transId];
        require (!txn.executed, "Transaction already executed");

        if (isConfirmed(transId)) {
            txn.executed = true;
            string memory assetName = miscellaneousData[transId][assetNameKeyName];
            address dest = abi.decode(bytes(miscellaneousData[transId][destAddressKeyName]), (address));

            transfer(transId, dest, assetName, txn.value);
        }
    }

    function submitWithdrawV1(address dest, uint256 withdrawAmount, uint256 amountWithFee, string memory assetName) public isWalletOwner(_msgSender()) {
    
        require (keccak256(abi.encodePacked("EUN")) != keccak256(abi.encodePacked(assetName)), 'EUN is not eligible to withdraw');
        address addr = internalSmartContractContract.getErc20SmartContractAddrByAssetName(assetName);
        require(addr != address(0), 'Asset not found');
        EurusERC20(addr).submitWithdraw(dest, withdrawAmount, amountWithFee);
        
        emit WithdrawRequestEvent(dest, withdrawAmount, assetName, amountWithFee);
    }

    function directTopUpPaymentWallet(uint256 targetGasWei, uint256 gasLimit) public isWalletOwner(_msgSender()){
        topUpPaymentWalletImpl(targetGasWei, gasLimit);
    }

    function topUpPaymentWallet(address paymentWalletAddr, uint256 targetGasWei, bytes memory signature) public onlyWriter(_msgSender()){
        require(paymentWalletAddr == walletOwner, 'Payment wallet address is not wallet owner address');
        bytes32 hashByte = keccak256(abi.encode(paymentWalletAddr));
        address senderAddr = verifySignature(hashByte, signature);
        require(senderAddr == walletOwner , 'Sender is not wallet owner');

        topUpPaymentWalletImpl(targetGasWei, 0);

    }

    function topUpPaymentWalletImpl(uint256 targetGasWei, uint256 gasLimit) internal {
        ExternalSmartContractConfig extConfig = ExternalSmartContractConfig( internalSmartContractContract.getExternalSCConfigAddress());
        
        require (targetGasWei <= extConfig.getMaxTopUpGasAmount(), 'Target gas exceed upper limit');
        uint256 gasPrice = extConfig.getEurusGasPrice();

        uint256 targetEun  = targetGasWei * gasPrice;
        uint256 currBalance = getWalletOwnerBalance() + gasLimit * gasPrice;
        require (currBalance <  targetEun , 'Payment wallet has the target gas amount already');

        uint256 transferEun = targetEun - currBalance;
        address self = payable(this);
        require(self.balance >= transferEun, 'EUN not enough in the account');
        
        payable(walletOwner).sendValue(transferEun);
        emit TopUpPaymentWalletEvent(walletOwner,  targetGasWei, transferEun/gasPrice);
    }

    function getWalletOwnerBalance() public view returns(uint256){
        return walletOwner.balance;
    }



    function invokeSmartContract(address scAddr, uint256 eun, bytes memory inputArg) public isWalletOwner(_msgSender()){
        assembly {            
            let d := add(inputArg, 32)
            let inputLen := mload(inputArg)
            let result := call(gas(), scAddr, eun, d, inputLen, 0, 0)
            let size := returndatasize()
            let ptr := mload(0x40)
            returndatacopy(ptr, 0, size)
            mstore(0x40, add(ptr, size))
            switch result
            case 0 { revert(ptr, size) }
            default { return (ptr, size) }
        }
    }
}
