import { FileOutlined, PieChartOutlined, UserOutlined,DesktopOutlined,TeamOutlined } from '@ant-design/icons';
import { HiUsers } from "react-icons/hi";
import { BiSupport, BiMoney } from "react-icons/bi";
import { AiFillFile } from "react-icons/ai";
import { Breadcrumb, Layout, Menu, theme } from "antd";
import { useState } from "react";
import { Outlet, useNavigate } from "react-router-dom";

import CustomFooter from '../custom/footer';
import CustomHeader from '../custom/header';

const { Header, Content, Footer, Sider } = Layout;
function getItem(label, key, icon, children) {
  return {
    key,
    icon,
    children,
    label,
  };
}
const items = [
  
  getItem('Dashboard', '/dashboard',  <DesktopOutlined />),
  getItem('All-Products', '/dashboard/product',<PieChartOutlined /> ),
  getItem('Profile', '/dashboard/update', <FileOutlined />),
  getItem('Products', 'sub1', <UserOutlined />, [
    getItem('Create', '/dashboard/createproduct'),
    getItem('Product-list', '4'),
  ]),
  getItem('User', 'sub2', <TeamOutlined />, [getItem('Create', '6'), getItem('All-user', '8')]),
  getItem('Transaction', '/dashboard/payment', <BiMoney />),
  
];

const BaseLayout = () => {
  const navigate = useNavigate();
  const [collapsed, setCollapsed] = useState(false);
  const {
    token: { colorBgContainer },
  } = theme.useToken();

  const onClick = (e) => {
    navigate(`${e.key}`);
  };
  return (
    <Layout className=''
      style={{
        minHeight: "100vh",
      }}
    >
      <Sider
        collapsible
        collapsed={collapsed}
        onCollapse={(value) => setCollapsed(value)}
      >
        <div
          style={{
            height: 32,
            margin: 16,
            background: "rgba(255, 255, 255, 0.2)",
          }}
        />
        <Menu
          theme="dark"
          className="text-md"
          defaultSelectedKeys={["1"]}
          mode="inline"
          items={items}
          onClick={onClick}
        />
      </Sider>
      <Layout className="site-layout h-[100%]">
        <Header
          style={{
            padding: 0,
            background: "none",
          }}
        >
           <CustomHeader/>
        </Header>
        <Content
          style={{
            margin: "0 16px",
          }}
        >
          <Breadcrumb
            style={{
              margin: "16px 0",
            }}
          >
            
          </Breadcrumb>
          <div
            style={{
              padding: 24,
              minHeight: 360,
              background: colorBgContainer,
            }}
          >
            <Outlet />
          </div>
        </Content>
        <Footer
          style={{
            padding: 0,
            textAlign: "center",
            
          }}
        >
         <CustomFooter/>
        </Footer>
      </Layout>
    </Layout>
  );
};

export default BaseLayout;