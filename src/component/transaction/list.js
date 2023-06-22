import { Space, Tooltip ,Table, Button, Input, Form} from 'antd';
import moment from 'moment/moment';
import React, { useEffect, useState } from 'react'
import { FiEdit } from "react-icons/fi";
import ReactPaginate from 'react-paginate';
import { GetPaymentType } from '../../service';
import { BankList_Type, payment_typeList } from '../common/function';

const List = () => {
  const [loading, setLoading] = useState(false);
  const [data,setData]=useState()
  console.log(data,'data')
  const [CurrentPageNumber,setCurrentPageNumber]=useState(1)
  const[searchTerm,setSearchTerm]=useState('')
  console.log('first',searchTerm)

  const listData=async()=>{
    setLoading(true)
    await GetPaymentType()
    .then((res)=>{
      console.log({res})
      setData(res.data)
      setLoading(false)
    })
    .catch((err)=>{
      setTimeout(()=>{
        setLoading(false)
      },1000)
    })
  }
  

  const onFinish=()=>{
    console.log('000000')
    const keys=['check_bank','reference_no','payment_amount']
   const res=data.filter((item,index) => 
   keys.some((key)=>item[key].toLowerCase().includes(searchTerm))
  //  item?.check_bank.toLowerCase().includes(searchTerm) 
  //  ||  item?.reference_no?.toLowerCase().includes(searchTerm) || item?.payment_amount?.toLowerCase().includes(searchTerm) 
   )
   setData(res)

  }
  const handelclick=()=>{
document.getElementById('form_data').reset()
listData()
  }

  

  useEffect(()=>{
    listData()
  },[])

  const columns = [
    {
      title: "SL",
      dataIndex: "index",
      width: "40px",
      render: (value, item, index) => index + 1,
    },
   
    {
      title: "payment_type",
      dataIndex: "payment_type",
      showOnResponse: true,
      showOnDesktop: true,
      render: (_, { payment_type }) => (
        <>{payment_typeList(payment_type)}</>
      ),
    },
    {
      title: "bank_account",
      dataIndex: "bank_account",
      showOnResponse: true,
      showOnDesktop: true,
      render:(_,{bank_account})=>(
        <>{BankList_Type(bank_account)}</>
      )
      
    },
 

     {
      title: "deposite_date",
      dataIndex: "deposite_date",
      showOnResponse: true,
      showOnDesktop: true,
      render: (_, { deposite_date }) => (
        <>
          {deposite_date ? (
            <>{moment(deposite_date).format("DD-MMM-yyyy")}</>
          ) : (
            <>N/A</>
          )}
        </>
      ),
    },
    {
      title: "payment_amount ",
      dataIndex: "payment_amount",
      showOnResponse: true,
      showOnDesktop: true,
    },

    {
      title: "reference_no ",
      dataIndex: "reference_no",
      showOnResponse: true,
      showOnDesktop: true,
    },
   
    
    {
      title: "Action",
      dataIndex: "priceSelling",
      showOnResponse: true,
      showOnDesktop: true,

      render: (value, obj, indx) => {
        // console.log(obj,value, "item");
        return (
          <Space size="middle">
            <a
              
            >
              <Tooltip placement="topLeft" title={"Edit"} color={"#87d068"}>
                <FiEdit style={{ fontSize: "20px", color: "green" }} />
              </Tooltip>
            </a>
          </Space>
        );
      },
    },
  ];

  return (
    <>
    <Form onFinish={onFinish} id='form_data'>
    <div className='flex flex-row justify-end gap-4'>
            <div>
                <Form.Item
                name="Search"
                rules={[
                  {
                    required: true,
                    message: "Please input your username!",
                  },
                ]}
              >
               <Input
                 className='w-[220px] md:w-[320px]'
                   style={{
                     height: "40px",
                   }}
                   placeholder="Reference NO/Payment Amount"
                   onChange={(e)=>{
                    setSearchTerm(e.target.value)
                   }}
                  
                 />
      
               </Form.Item>
            </div>
      <Button type='button' className='h-[40px] w-[150px] bg-orange-600 text-white'  htmlType="submit">Search </Button>
      <Button type='button' className='h-[40px] w-[150px] bg-green-600 text-white' onClick={handelclick}>clear </Button>


    </div>
    </Form>
  


    <div className='flex flex-col md:flex-row border-b-2 border-red-400'>
      <p className='text-xl font-bold text-gray-400 mt-6'>Deposite Bank</p>
    </div>
    <Table
        columns={columns}
        dataSource={data}
        size="small"
        loading={loading}
        className="mt-4"
        scroll={{
          y: 700,
          x: "1000px",
        }}
        mobileBreakPoint={768}
        pagination={false}
        rowKey={dataSource => dataSource.id}
      />

                  {/* <ReactPaginate
                        previousLabel={"previous"}
                        // forcePage={currentPageNumber - 1}
                        nextLabel={"next"}
                        breakLabel={"..."}
                        // pageCount={pageCount}
                        marginPagesDisplayed={2}
                        pageRangeDisplayed={3}
                        onPageChange={handlePageClick}
                        containerClassName={"pagination justify-content-center"}
                        pageClassName={"page-item"}
                        pageLinkClassName={"page-link"}
                        previousClassName={"page-item"}
                        previousLinkClassName={"page-link"}
                        nextClassName={"page-item"}
                        nextLinkClassName={"page-link"}
                        breakClassName={"page-item"}
                        breakLinkClassName={"page-link"}
                        activeClassName={"active"}
                      /> */}
    </>
  )
}

export default List