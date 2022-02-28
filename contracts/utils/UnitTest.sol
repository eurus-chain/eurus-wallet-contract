pragma solidity >=0.6.0 <0.8.0;

contract UnitTest {
    int public value;
    address public lastModifiedBy;

    function InvokeRequireMessage(int i ) public{
        require(false, "Require is triggered");
        value = i;
    }

    function SetValue(int i ) public {
        value = i;
        lastModifiedBy = msg.sender;
    }
}
