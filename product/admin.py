from django.contrib import admin
from .models import *

# register your models here.
admin.site.register(Payment_type)
admin.site.register(payment_bank)
admin.site.register(payment_name)
admin.site.register(Customer)


# //product model register

admin.site.register(Products_Unit)
admin.site.register(Ecom_item_type)
admin.site.register(Ecom_Product_Sub_Categories)
admin.site.register(Ecom_Products)