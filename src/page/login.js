import React, { useState } from "react";
import { Button, Checkbox, Form, Input, message } from "antd";
import { LockOutlined, UserOutlined } from "@ant-design/icons";
import { Link, useNavigate } from "react-router-dom";
import { login } from "../service";

const Login = () => {
  const navigate = useNavigate();
  const [userData, setUserData] = useState({
    email: "",
    Password: "",
  });

  const onFinish = async () => {
  console.log(userData,'userData')

let payload={
  username: userData?.email,
  password: userData?.Password,
}
login(payload)
 .then((res)=>{
  let user=res?.config.data
  user=JSON.parse(user)
  localStorage.setItem('user',JSON.stringify(user))
  console.log(res,'datares')
  if(res?.data?.access !==null & res?.data?.access !== undefined && res?.data?.access !==""){
    navigate('/dashboard')
    localStorage.setItem('token',JSON.stringify(res?.data?.access))
  }
 })
 .catch((error)=>{
  // console.log(error)
 })
  };

  return (
    <div
      style={{ height: "700px" }}
      className="flex items-center justify-center"
    >
      <div className="p-10  max-w-md mx-auto bg-white rounded-md shadow-2xl flex justify-center ">
        <Form onFinish={onFinish}>
          <Form.Item
            name="username"
            rules={[
              {
                required: true,
                message: "Please input your username!",
              },
            ]}
          >
            <Input
              style={{
                width: "310px",
                height: "40px",
              }}
              prefix={<UserOutlined className="site-form-item-icon" />}
              placeholder="Username"
              onChange={(e) => {
                setUserData({
                  ...userData,
                  email: e.target.value,
                });
              }}
            />
          </Form.Item>

          <Form.Item
            // label="Password"
            name="password"
            rules={[
              {
                required: true,
                message: "Please input your password!",
              },
            ]}
          >
            <Input.Password
              style={{
                width: "310px",
                height: "40px",
              }}
              prefix={<LockOutlined className="site-form-item-icon" />}
              placeholder="Password"
              onChange={(e) => {
                setUserData({
                  ...userData,
                  Password: e.target.value,
                });
              }}
            />
          </Form.Item>

          <div className="flex justify-between items-center pb-5">
            <div>
              <Form.Item
                className="mb-0"
                name="remember"
                valuePropName="checked"
              >
                <Checkbox>Remember me</Checkbox>
              </Form.Item>
            </div>

            <Link to="/forgotpassword">
              <div className="text-[#703E97] pl-20 font-bold">
                Forget Password
              </div>
            </Link>
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
                Sign In
              </Button>
            </Form.Item>
          </div>
          <div className="flex justify-center pt-3 mb-0">
            <p className="">{"Don't have an account?"}</p>
            <Link to="/register">
              <p className="text-[#703E97] font-bold px-2" cursor="pointer">
                {" "}
                {"Register Now"}
              </p>
            </Link>
          </div>
        </Form>
      </div>
    </div>
  );
};

export default Login;