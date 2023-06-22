import React from 'react'
import {
    BsTelephonePlusFill,
    BsYoutube,
    BsTwitter,
    BsInstagram,
  } from "react-icons/bs";
  import { FaLinkedinIn, FaFacebook } from "react-icons/fa";
import { Link } from 'react-router-dom';
import cash_logo from '../../../images/logo.jpg.webp'
const itemlist=[
    {title:'FAQ',path:''},
    {title:'Contact',path:''},
    {title:'About-us',path:''},
  ]
  
  const listitem=[{
    title:'Terms&Condition'
  },
  {title:'Emi Policy'},
  {title:'Privecy&Policy'}]
  

  const socials = [
    { name: FaFacebook, path: "https://www.facebook.com/triploverbd" },
    {
      name: BsYoutube,
      path: "https://www.youtube.com/channel/UCf0d1Rf2V9mBjQmprn9aZhQ",
    },
    {
      name: FaLinkedinIn,
      path: "https://www.linkedin.com/company/triplover/?viewAsMember=true",
    },
    { name: BsInstagram, path: "https://www.instagram.com/triplover.bd/" },
  ];


const CustomFooter = () => {
  return (
    <div>
        <div className='flex flex-col px-10 pt-3  justify-between md:flex-row  '>
            <div>
                <p className='text-xl font-bold text-gray-700 text-start border-b-2 border-rose-500'>Quick Links</p>
                {itemlist.map((item,index)=>{
                    return <div>
                         <p className='text-start text-lg text-gray-500'>{item.title}</p>
                        </div>
                })}
            </div>
            <div>
                <p className='text-xl font-bold text-gray-700 text-start border-b-2 border-rose-500'>Informations</p>
            {listitem.map((item,index)=>{
                    return <div>
                         <p className='text-start text-lg text-gray-500'>{item.title}</p>
                        </div>
                })}
            </div>
            <div>
                <p className='text-xl font-bold text-gray-700 text-start border-b-2 border-rose-500'>Follow-Us</p>
                {
                    socials.map((item,index)=>{
                        return<div className='rounded-full gap-5 bg-red shadow-xl'>
                        <Link to={item?.path}>
                      
                        </Link>
          
                            </div>
                    })
                }
            </div>

            <div>
                <p className='text-start text-lg text-gray-500'>
                    <img src={cash_logo} alt='' style={{height:'120px',width:'300px'}}/>
                </p>
            </div>

        </div>
    </div>
  )
}

export default CustomFooter;