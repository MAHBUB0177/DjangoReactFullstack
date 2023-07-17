import {  Divider, Form, message, Select } from 'antd'
import React, { useEffect, useState } from 'react'
import { createTransction, GetBankAccount, requestType } from '../../service'
import Bankdeposit from './bankDeposit'
import BankTransfer from './bankTransfer'
import Cheque from './cheque'

const Payment = () => {
    const[paymentType,setPaymentType]=useState()
    const[bankAcc,setBankAcc]=useState()

//set paylod all from submit
   const [payload,setPyload]=useState({
    payment_id:Math.floor(Math.random() * 16),
    payment_type:1,
    payment_amount:'',
    check_bank:'',
    deposite_date:'',
    reference_no:'',
    bank_account:'',
    branch:''
   })

    const GetpaymentType=()=>{
        requestType().then((res)=>{
            setPaymentType(res.data)
        }).catch((error)=>{
            console.log(error)
    
        })
    }
    const getBankAcconut=()=>{
      try{
        GetBankAccount().then((res)=>{
          setBankAcc(res.data)
        })
        .catch((err)=>{
          console.log(err)
        })
      }
      catch(err){
        console.log(err)

      }
    }
    useEffect(()=>{
        GetpaymentType()
        getBankAcconut()
    },[])


  
    const onFinish=()=>{
        console.log('okkkk',payload)
        try{
          createTransction(payload).then((res)=>{
            // console.log(res,'data12345')
            message.success('successfully done!')
            document.getElementById('payment_id').reset()
          }).catch((err)=>{
            console.log(err)
          }) 
        }
        catch(err){
          message.error('something went wrong!')
        }

    }

    const result = paymentType?.map((a) => ({ value: a.paymenttype_id, label: a.payment_name }));
    console.log(result)
    const bankAccount=bankAcc?.map((a)=>({value:a.bank_id,label:a.payment_bank
    }))

 
  return (
    <>
    <Form onFinish={onFinish} id='payment_id'>
            <div className=' grid grid-cols-1 mt-3 '>
               <Form.Item
                     name="bank_acc"
                     rules={[
                       {
                         required: true,
                         message: "Please input your type!",
                       },
                     ]}
                  >
                    <p className="mb-0 font-bold">
                      Select Type 
                    </p>
                    <Select 
                      name="passengerType"
                      size="large"
                      style={{
                        width: "100%",
                      }}
                      placeholder='Select Type'
                      onChange={(value) => {
                        setPyload({
                          ...payload,
                          payment_type: Number(value),
                        });
                      }}
                      options={result}
                    >

                     
                    </Select>
                  </Form.Item>

            </div>
   
    <Divider orientation="left"  >Submit Request</Divider>
    {
        payload.payment_type === 1 ? <Cheque setPyload={setPyload} payload={payload} bankAccount={bankAccount} /> :
        payload.payment_type===2 ? <BankTransfer setPyload={setPyload} payload={payload} bankAccount={bankAccount}/> :
        payload.payment_type===3 ?<Bankdeposit setPyload={setPyload} payload={payload} bankAccount={bankAccount}/>:
        ''
    }
     
     </Form>
    </>
  )
}

export default Payment