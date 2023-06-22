import { Button, DatePicker, Form, Input, message, Select, Upload } from 'antd'
import React from 'react'
import { UploadOutlined } from "@ant-design/icons";

const BankTransfer = ({setPyload,payload,bankAccount}) => {

  const props = {
    name: "file",
    action: "https://www.mocky.io/v2/5cc8019d300000980a055e76",
    headers: {
      authorization: "authorization-text",
    },
    onChange(info) {
    //   setShowupload(true);
      if (info.file.status !== "uploading") {
        var file = new FormData();
        file.append(`file`, info.fileList[0].originFileObj);
       
      }
      if (info.file.status === "done") {
        // setShowupload(false);
        message.success(`${info.file.name} file uploaded successfully`);
      } else if (info.file.status === "error") {
        // setShowupload(false);
        message.error(`${info.file.name} file upload failed.`);
      }
    },
  };

  const onChange = (date, dateString) => {
    console.log(date, dateString);
    setPyload({
      ...payload,
      deposite_date: dateString,
    });
  };
  
  return (
    <>
     <div className='flex flex-col md:flex-row gap-3 flex-wrap '>
     <Form.Item
       name="date"
       rules={[
         {
           required: true,
           message: "Please input your password!",
         },
       ]}
     >
       <DatePicker
         onChange={onChange}
         className='w-[220px] md:w-[320px]'
         style={{
           // width: "310px",
           height: "40px",
         }}
        
       />
     </Form.Item>


     <Form.Item
       name="Reference"
       rules={[
         {
           required: true,
           message: "Please input your username!",
         },
       ]}
     >
               <Input
                 value={payload?.reference_no}
                 className='w-[220px] md:w-[320px]'
                   style={{
                     height: "40px",
                   }}
                   placeholder="Reference"
                   onChange={(e)=>{
                     setPyload({
                      ...payload,
                       reference_no:e.target.value
                     })
                   }}
                 />
      
     </Form.Item>

     <Form.Item
       name="bank_acc"
       rules={[
         {
           required: true,
           message: "Please input your username!",
         },
       ]}
     >
              <Select
                 className='w-[220px] md:w-[320px]'
                 size='large'
                   style={{
                     width: "320px",
                     height: "40px",
                   }}
                   options={bankAccount}
                   placeholder='select bank_acc'
                   onChange={(value)=>{
                     setPyload({
                       ...payload,
                       bank_account:Number(value)
                     })
                   }}
                 />
      
     </Form.Item>

     <Form.Item
       name="Amount"
       rules={[
         {
           required: true,
           message: "Please input your Amount!",
         },
       ]}
     >
               <Input
                 value={payload?.reference_no}
                 className='w-[220px] md:w-[320px]'
                   style={{
                     height: "40px",
                   }}
                   placeholder="Amount"
                   onChange={(e)=>{
                     setPyload({
                      ...payload,
                      payment_amount:e.target.value
                     })
                   }}
                 />
      
     </Form.Item>


     <Form.Item
       name="File"
       rules={[
         {
           required: false,
           message: "Please input your Amount!",
         },
       ]}
     >
       <Upload
           size="large"
           style={{ backgroundColor: "purple" }}
           {...props}
           maxCount={1}
           // showUploadList={showupload}
         >
           <Button className='w-[220px] md:w-[320px]'
             icon={
               <UploadOutlined
                 style={{
                   color: "white",
                   fontSize: "20px",
                 }}
               />
             }
             style={{
               // width: "320px",
               height: "40px",
               backgroundColor: "purple",
               color: "white",
             }}
           >
             File
           </Button>
         </Upload>
      
     </Form.Item>
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
     </div></>
  )
}

export default BankTransfer