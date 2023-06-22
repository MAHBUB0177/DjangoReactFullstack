import { Divider, Radio } from 'antd'
import React, { useState } from 'react'
import { Items, List, Payment } from '../component/transaction'

const Transaction = () => {
    const[type,setType]=useState('a')
    console.log(type)
    
  return (
    <>
    <Radio.Group defaultValue={type} buttonStyle="solid" size="large" style={{}}
          onChange={(e) => setType(e.target.value)}>
      <Radio.Button value="a">Payment</Radio.Button>
      <Radio.Button value="b">List</Radio.Button>
      <Radio.Button value="c">Items</Radio.Button>
    </Radio.Group>
  

    {
        type=== 'a'? <Payment/> : type === 'b' ? <List/> : type==='c' ? <Items/> :''
    }
    </>
  )
}

export default Transaction