
import './App.css';
import Routers from './routes';
import axiosInstance from './service/httpService'

function App() {

  const token=JSON.parse(localStorage.getItem('token'))
  axiosInstance.interceptors.request.use(async (config) => {
    if (token) {
      config.headers.Authorization = `Bearer ${token}`;
    }
    return config;
  });
  return <Routers/>
}

export default App;
