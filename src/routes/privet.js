import React from "react";
import { Navigate, useLocation } from "react-router-dom";

const Private = ({ children, ...rest }) => {
  const location = useLocation();
  const token=JSON.parse(localStorage.getItem('token'))
  if (token) {
    return children;
  }
  return <Navigate to="/" state={{ from: location }} />;
};

export default Private;