
const deposittype = [
    {id:1,name:'cash'},
    {id:2,name:'Bank_Deposite'},
    {id:3,name:'Cheque'}
  ];

  export const payment_typeList=(id)=>{
  return deposittype.find((item)=>item?.id == id)?.name
  }

  const bank_accountList=[
    {id:1,name:'Uttora Bank'},
    {id:2,name:'Gramin Bank'},
    {id:3,name:'Brack Bank'},
    {id:4,name:'City Bank'},
    {id:5,name:'EBL Bank'}
  ]

  export const BankList_Type=(id)=>{
    return bank_accountList.find((item)=>item?.id == id)?.name
  }