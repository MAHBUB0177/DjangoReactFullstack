import { Button, DatePicker, Form, Input, Modal, Select, message,Space, Tooltip ,Table,columns } from 'antd';
import React from 'react'
import { useState } from 'react';
import { useEffect } from 'react'
import { createProduct, DeleteProduct, getagent, Getcategories ,getproductList,getProductUnit, subcatgories, UpdateProduct} from "../service";
import { FiEdit } from 'react-icons/fi';
import { AiOutlineDelete } from 'react-icons/ai';
import customParseFormat from "dayjs/plugin/customParseFormat";
import dayjs from "dayjs";
dayjs.extend(customParseFormat);

const Products = () => {

    const [catagories,setCatagorise]=useState([])
    const [units,setUnits]=useState([])
    const [subCategroise,setSubCategroise]=useState([])
    const [payload,setPayload]=useState({
        id:Math.floor(Math.random() * 16),
        // id:'9',
        category_id:'',
        sub_category_id:'',
        unit_id:'',
        product_name:'',
        Agen_name:'',
        product_model:'',
        product_price:'',
        purchase_date:'',
        discount_amount:'',
        product_old_price:'',
        stock_limit:'',
        app_user_id:'admin'
    })

    console.log('payload',payload)
    
    const [modalTitle, setModalTitle] = useState("ADD");
    const dateFormat = "YYYY-MM-DD";
    const [isModalOpen, setIsModalOpen] = useState(false);
    const [form] = Form.useForm();
    const handleCancel = () => {
        setIsModalOpen(false);
        document.getElementById("create-course-form").reset();
      };

      const categories=catagories?.map((item)=>({value:item?.categories_id,label:item?.categories_name}))
      // console.log(categories,'categories')
      const unit=units?.map((item)=>({value:item?.unit_id,label:item?.unit_name}))
      // const agent=agents?.map((item)=>({value:item?.agent_id,label:item?.agent_name}))
      const sub_categories=subCategroise?.map((item)=>({value:item?.subcategories_id,label:item?.subcategories_name}))
      
    const GetCategori=async()=>{
        Getcategories().then((res)=>{
            setCatagorise(res.data)
        })
    }
    const getProdUnits=async()=>{
        getProductUnit().then((res)=>{
            setUnits(res.data)
        })
    }

    const sub_categorie=async()=>{
        subcatgories().then((res)=>{
            setSubCategroise(res.data)
        })
    }  
    const onChange = (date, dateString) => {
      // console.log(date, dateString);
      setPayload({
          ...payload,
          purchase_date:dateString
      })
    };

  const[allproduct,setAllproduct]=useState()
  const[loading,setLoading]=useState()

    const getAllProduct=async()=>{
      setLoading(true)
      await getproductList().then((res)=>{
        setAllproduct(res.data)
        setLoading(false)
      })
      .catch((err)=>{
        setLoading(false)
        // console.log(err)
      })
    }
    useEffect(()=>{
        GetCategori()
        getProdUnits()
        getAllProduct()
        // agentList()
        sub_categorie()
    },[])

    const onFinish=()=>{
        console.log('firstpayload',payload)
        if (modalTitle === 'ADD PRODUCT'){
          createProduct(payload).then((res)=>{
            setIsModalOpen(false)
            getAllProduct()
            document.getElementById("create-course-form").reset();
            message.success('successfully ctreate product!')
          })
          .catch((error)=>{
            setIsModalOpen(false)
            // console.log(error)
          })
        }
        else{
          UpdateProduct(payload).then((res)=>{
            setIsModalOpen(false)
            getAllProduct()
            document.getElementById("create-course-form").reset();
            message.success('successfully Update product!')
          })
          .catch((error)=>{
            setIsModalOpen(false)
            // console.log(error)
          })
        }
        
    }

    const hadeldeleteitem=(id)=>{
      
      DeleteProduct(id).then((res)=>{
        message.success('delete successfully')
      })

    }
    


const columns = [
        {
          title: "SL",
          dataIndex: "index",
          width: "40px",
          render: (value, item, index) => index + 1,
        },
       
        {
          title: "Product Name",
          dataIndex: "product_name",
          showOnResponse: true,
          showOnDesktop: true,
         
        },
        {
          title: "Product Model",
          dataIndex: "product_model",
          showOnResponse: true,
          showOnDesktop: true,
          
        },

        {
          title: "Product Price",
          dataIndex: "product_price",
          showOnResponse: true,
          showOnDesktop: true,
          
        },
     
    
         {
          title: "Cateogries ",
          dataIndex: "category_id",
          showOnResponse: true,
          showOnDesktop: true,
          render: (_, { category_id }) => (
            <>
              {category_id ? (
                <>{ category_id?.categories_name}</>
              ) : (
                <>N/A</>
              )}
            </>
          ),
        },
        {
          title: "Unit ",
          dataIndex: "unit_id",
          showOnResponse: true,
          showOnDesktop: true,
          render: (_, { unit_id }) => (
            <>
              {unit_id ? (
                <>{ unit_id?.unit_name}</>
              ) : (
                <>N/A</>
              )}
            </>
          ),
        },
    
        {
          title: "Action",
          dataIndex: "priceSelling",
          showOnResponse: true,
          showOnDesktop: true,
    
          render: (value, obj, indx) => {
            console.log(obj,value, "item");
            return (
              <Space size="middle">
                <a onClick={()=>{
                 form.setFieldsValue({
                  category_id: obj.category_id?.categories_id,
                  sub_category_id: obj.sub_category_id?.subcategories_id,
                  unit_id: obj.unit_id?.unit_id,
                  product_name: obj.product_name,
                  product_model: obj.product_model,
                  product_price:obj.product_price,
                  discount_amount:obj?.discount_amount,
                  product_old_price:obj?.product_old_price,
                  stock_limit:obj.stock_limit,
                  purchase_date:obj.app_data_time !== null
                  ? dayjs(obj?.app_data_time, dateFormat)
                  : "",
                })
                setPayload({
                  product_id:obj?.product_id,
                  category_id: obj?.category_id?.categories_id,
                  sub_category_id: obj?.sub_category_id?.subcategories_id,
                  unit_id: obj?.unit_id?.unit_id,
                  product_name: obj?.product_name,
                  product_model: obj?.product_model,
                  product_price:obj?.product_price,
                  discount_amount:obj?.discount_amount,
                  product_old_price:obj?.product_old_price,
                  stock_limit:obj?.stock_limit,
                  purchase_date:obj?.app_data_time !== null
                  ? dayjs(obj?.app_data_time, dateFormat)
                  : "",});
                setIsModalOpen(true)
                setModalTitle('Edit PRODUCT')
                }}
                >
                  <Tooltip placement="topLeft" title={"Edit"} color={"#87d068"}>
                    <FiEdit style={{ fontSize: "20px", color: "green" }} />
                  </Tooltip>
                </a>

                <a onClick={()=>hadeldeleteitem(obj?.product_id)}>
                  
                  <Tooltip placement="topLeft" title={"delete"} color={"red"}>
                    <AiOutlineDelete style={{ fontSize: "20px", color: "red" }} />
                  </Tooltip>
                </a>
              </Space>
            );
          },
        },
      ];

    
  return (
    <div>
        <div className='flex flex-col justify-between md:flex-row   border-b-2 border-b-orange-500 pb-3'>
            <p className='text-xl font-bold text-start'>Product List</p>
            <Button type='button' className='bg-green-400 text-white text-md h-[40px]' onClick={()=>{
                setIsModalOpen(true)
                setModalTitle('ADD PRODUCT')
            }}>
                Create Product
            </Button>

            <Modal
            title={modalTitle}
            className="text-2xl"
            open={isModalOpen}
            width={1000}
            onCancel={handleCancel}
            footer={null}
            maskClosable={false}
        >
            <div className="border-b-2 border-#bbc5d3 mb-5"></div>
           
         <Form onFinish={onFinish} id='create-course-form' form={form}>
            <div className='grid grid-cols-4 gap-3'>
            <div>
            <Form.Item
            name="category_id"
            rules={[
              {
                required: false,
                message: "Please input your category_id!",
              },
            ]}
             >
                   <Select
                   value={payload?.category_id}
                      className='w-[220px] md:w-[320px]'
                      size='large'
                        style={{
                          width: "220px",
                          height: "40px",
                        }}
                        options={categories}
                        placeholder='select Catagories'
                        onChange={(value)=>{
                            setPayload({
                                ...payload,
                                category_id:Number(value)

                            })
                        }}

                        
                       
                      />
           
          </Form.Item>
            </div>

            <div>
            <Form.Item
            name="sub_category_id"
            rules={[
              {
                required: false,
                message: "Please input your sub_category_id!",
              },
            ]}
             >
                   <Select
                   value={payload?.sub_category_id}
                      className='w-[220px] md:w-[320px]'
                      size='large'
                        style={{
                          width: "220px",
                          height: "40px",
                        }}
                        options={sub_categories}
                          onChange={(value)=>{
                            setPayload({
                                ...payload,
                                sub_category_id:Number(value)

                            })
                        }}
                        placeholder='select sub_Categories'
                       
                      />
           
          </Form.Item>
            </div>

            <div>
            <Form.Item
            name="unit_id"
            rules={[
              {
                required: false,
                message: "Please input your unit_id!",
              },
            ]}
             >
                   <Select
                   value={payload?.unit_id}
                      className='w-[220px] md:w-[220px]'
                      size='large'
                        style={{
                          width: "220px",
                          height: "40px",
                        }}
                        options={unit}
                         onChange={(value)=>{
                            setPayload({
                                ...payload,
                                unit_id:Number(value)

                            })
                        }}
                        placeholder='select Units'
                       
                      />
           
          </Form.Item>
            </div>


        


            <div>
            <Form.Item
            name="purchase_date"
            rules={[
              {
                required: false,
                message: "Please input your purchase_date!",
              },
            ]}
          >
            <DatePicker
            value={payload?.purchase_date}
            // format={dateFormat}
              onChange={onChange}
              className='w-[220px] md:w-[220px]'
              style={{
                // width: "310px",
                height: "40px",
              }}
             
            />
          </Form.Item>
            </div>

         <div>
         <Form.Item
            name="product_name"
            rules={[
              {
                required: true,
                message: "Please input your product_name!",
              },
            ]}
          >
                    <Input
                      value={payload?.product_name}
                      className='w-[220px] md:w-[220px]'
                        style={{
                          height: "40px",
                        }}
                        onChange={(e)=>{
                            setPayload({
                                ...payload,
                                product_name:e.target.value

                            })
                        }}
                        placeholder="product_name"
                        
                      />
           
          </Form.Item> 
         </div>

         <div>
         <Form.Item
            name="product_model"
            rules={[
              {
                required: true,
                message: "Please input your product_model!",
              },
            ]}
          >
                    <Input
                      value={payload?.product_model}
                      className='w-[220px] md:w-[220px]'
                        style={{
                          height: "40px",
                        }}
                        onChange={(e)=>{
                            setPayload({
                                ...payload,
                                product_model:e.target.value

                            })
                        }}
                        placeholder="product_model"
                        
                      />
           
          </Form.Item> 
         </div>

         <div>
         <Form.Item
            name="product_price"
            rules={[
              {
                required: true,
                message: "Please input your product_price!",
              },
            ]}
          >
                    <Input
                      value={payload?.product_price}
                      className='w-[220px] md:w-[220px]'
                        style={{
                          height: "40px",
                        }}
                        onChange={(e)=>{
                            setPayload({
                                ...payload,
                                product_price:e.target.value

                            })
                        }}
                        placeholder="product_price"
                        
                      />
           
          </Form.Item> 
         </div>


         <div>
         <Form.Item
            name="discount_amount"
            rules={[
              {
                required: true,
                message: "Please input your discount_amount!",
              },
            ]}
          >
                    <Input
                      value={payload?.discount_amount}
                      className='w-[220px] md:w-[220px]'
                        style={{
                          height: "40px",
                        }}
                        onChange={(e)=>{
                            setPayload({
                                ...payload,
                                discount_amount:e.target.value

                            })
                        }}
                        placeholder="discount_amount"
                        
                      />
           
          </Form.Item> 
         </div>

         <div>
         <Form.Item
            name="product_old_price"
            rules={[
              {
                required: true,
                message: "Please input your product_old_price!",
              },
            ]}
          >
                    <Input
                      value={payload?.product_old_price}
                      className='w-[220px] md:w-[220px]'
                        style={{
                          height: "40px",
                        }}
                        onChange={(e)=>{
                            setPayload({
                                ...payload,
                                product_old_price:e.target.value

                            })
                        }}
                        placeholder="product_old_price"
                        
                      />
           
          </Form.Item> 
         </div>

         <div>
         <Form.Item
            name="stock_limit"
            rules={[
              {
                required: true,
                message: "Please input your stock_limit!",
              },
            ]}
          >
                    <Input
                      value={payload?.stock_limit}
                      className='w-[220px] md:w-[220px]'
                        style={{
                          height: "40px",
                        }}
                        onChange={(e)=>{
                            setPayload({
                                ...payload,
                                stock_limit:e.target.value

                            })
                        }}
                        placeholder="stock_limit"
                        
                      />
           
          </Form.Item> 
         </div>
            </div>
            <div className="flex items-center justify-center">
            <Form.Item className="mb-0">
              <Button
                className="text-white bg-gradient-to-br from-pink-500 to-orange-400 hover:bg-gradient-to-bl focus:ring-4 focus:outline-none focus:ring-pink-200 dark:focus:ring-pink-800 font-medium rounded-lg text-sm px-5 py-2.5 text-center mr-2 mb-2"
                style={{
                  width: "250px",
                  height: "40px",
                  // background: "green",
                  color: "white", 
                }}
                htmlType="submit"
              >
               Submit
              </Button>
            </Form.Item>
          </div>

         </Form>
        
        </Modal>
        </div>
        <Table
        columns={columns}
        dataSource={allproduct}
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

    
    </div>
  )
}

export default Products