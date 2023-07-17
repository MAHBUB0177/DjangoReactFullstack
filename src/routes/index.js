import React from 'react'
import { Route, Routes } from "react-router-dom";
import BaseLayout from '../component/layout';
import Login from '../page/login';
import Product from '../page/product';
import Products from '../page/products';
import Transaction from '../page/transaction';
import Update from '../page/update';
import Private from './privet';
const Routers = () => {
  return (
    
         <Routes>
             <Route path="/" element={<Login />} />
             <Route
                path="/dashboard"
                element={
                  <Private>
                    <BaseLayout />
                  </Private>
                }
            >
        <Route path="product" element={<Product />} />
        <Route path="update" element={<Update />} />
        <Route path="payment" element={<Transaction />} />
        <Route path="createproduct" element={<Products />} />
      </Route>

         </Routes>
  )
}

export default Routers;