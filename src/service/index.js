
import axiosInstance from "./httpService";

// login user
export const login = (payload) => {
    console.log(payload,'payload')
  let url = `api/gettoken/`;
  return axiosInstance.post(url, payload);
};

export const requestType=()=>{
  let url=`api/payment_name/`
  return axiosInstance.get(url)
}

export const GetBankAccount=()=>{
  let url=`api/payment_bank/`
  return axiosInstance.get(url)
}


export const createTransction = (payload) => {
  console.log(payload,'payload')
let url = `api/transaction_payment/`;
return axiosInstance.post(url, payload);
};

//get all type payment
export const GetPaymentType=()=>{
  let url=`api/paymenttype/`
  return axiosInstance.get(url)
}

export const Getcategories=()=>{
  let url=`api/categoris/`
  return axiosInstance.get(url)
}

export const getProductUnit=()=>{
  let url=`api/product-unit/`
  return axiosInstance.get(url)
}

export const getagent=()=>{
  let url=`api/payment_sellagent/`
  return axiosInstance.get(url)
}

export const subcatgories=()=>{
  let url=`api/product-subcategories/`
  return axiosInstance.get(url)
}
//create product items
export const createProduct = (payload) => {
  console.log(payload,'payload')
let url = `api/createproducts/`;
return axiosInstance.post(url, payload);
};

//update prouct
export const UpdateProduct = (payload) => {
  console.log(payload,'payload')
let url = `api/updateproducts/`;
return axiosInstance.post(url, payload);
};

export const DeleteProduct = (payload) => {
  console.log(payload,'payload00000000')
let url = `api/deleteproducts/`;
return axiosInstance.post(url, payload);
};


export const getproductList=()=>{
  let url='api/products/'
  return axiosInstance.get(url)
}