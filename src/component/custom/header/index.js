import { Dropdown, Form, Input, Space } from 'antd';
import React, { useState } from 'react'
import {
  LogoutOutlined,
  SearchOutlined,
  UserOutlined,
} from "@ant-design/icons";
import { useNavigate } from 'react-router-dom';


const CustomHeader = () => {

  const navigate=useNavigate()
  const [serachTerm,setSearchTerm]=useState('')
  console.log(serachTerm,'serachTerm')
  const onFinish=()=>{

  }

  let user=JSON.parse(localStorage.getItem('user'))

  const items = [
    {
      label: "Profile",
      key: "/dashboard/profile",
      icon: <UserOutlined />,
    },
    {
      label: "Logout",
      key: "2",
      icon: <LogoutOutlined />,
    },
  ];
  const handleMenuClick = (e) => {
    if (e.key === "2") {
      _handelLogout();
      // navigate(`${e.key}`);
    } else {
      navigate(`${e.key}`);
    }
  };

  const _handelLogout=()=>{
    console.log('first')
    localStorage.removeItem('token')
    navigate('/')
  }

  const menuProps = {
    items,
    onClick: handleMenuClick,
  };
  return (
    <div className='bg-[#ffffff] '>
        <div className='flex flex-col md:flex-row px-10 justify-between'>

            <div>
                <p className='text-2xl font-bold text-red-600 py-3'>OurShop</p>
            </div>

            <div className='hidden  space-x-6 md:flex'>
              <Form onFinish={onFinish}>
              <Form.Item>
              <Input
                className="border-2 border-rose-400 "
                style={{
                  marginTop:'12px',
                  width: "310px",
                  height: "40px",
                  borderRadius: "50px",
                }}
                suffix={<SearchOutlined style={{fontSize:'20px',color:'purple',fontWeight:'bold'}}  onClick={onFinish}/>}
                placeholder="Search Your Product..."
                onChange={(e) => {
                  setSearchTerm(e.target.value);
                }}
              />
            </Form.Item>
              </Form>
              
         <a href="#">
          <div className="text-md">
            <Space wrap>
              <Dropdown.Button
                menu={menuProps}
                icon={<UserOutlined  style={{color:'red',}}/>}
                placement="bottomRight"
                arrow
                size="large"
              >
              <h2  style={{color:'purple'}}> {user?.username}</h2>
              </Dropdown.Button>
            </Space>
          </div>
        </a>
            </div>
        </div>
    </div>
  )
}

export default CustomHeader;