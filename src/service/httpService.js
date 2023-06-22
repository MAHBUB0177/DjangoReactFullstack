import axios from "axios";
import{domain} from '../env'
const axiosInstance = axios.create({
  baseURL: `${domain}`,
});

export default axiosInstance;