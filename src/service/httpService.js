import axios from "axios";
import{domain} from '../env'


const axiosInstance = axios.create({
  baseURL: `${domain}`,
});

const token=JSON.parse(localStorage.getItem('token'))
  axiosInstance.interceptors.request.use(async (config) => {
    if (token) {
      config.headers.Authorization = `Bearer ${token}`;
    }
    return config;
  });

export default axiosInstance;